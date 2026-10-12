"""Regression checks for active-motion timing classification; no renderer needed."""
import unittest

from check_rendering import moving_intervals, stats, frame_profile_summary


def sample(at, moving):
    # The native harness records this timestamp AFTER App#update completes.
    return [at, "combat", 16.7, 2, moving]


class MotionIntervalsTest(unittest.TestCase):
    def test_idle_after_a_turn_handoff_does_not_become_an_animation_stall(self):
        gaps = moving_intervals([[0], [.092]], [sample(100, True), sample(100.016, False)], 100)
        self.assertEqual(1, len(gaps))
        self.assertAlmostEqual(16, gaps[0])

    def test_a_blocked_gui_with_no_new_updates_keeps_the_entire_stall(self):
        gaps = moving_intervals([[0], [.150]], [sample(100, True)], 100)
        self.assertAlmostEqual(150, gaps[0])

    def test_sustained_motion_still_fails_even_if_it_stops_just_before_paint(self):
        samples = [sample(100 + i / 100, True) for i in range(10)] + [sample(100.1, False)]
        gaps = moving_intervals([[0], [.110]], samples, 100)
        self.assertAlmostEqual(110, gaps[0])
        self.assertGreater(gaps[0], 60)

    def test_motion_that_starts_inside_an_idle_gap_is_measured(self):
        gaps = moving_intervals([[0], [.150]], [sample(100, False), sample(100.030, True)], 100)
        self.assertAlmostEqual(120, gaps[0])

    def test_idle_and_separate_motion_bursts(self):
        self.assertEqual([], moving_intervals([[0], [.2]], [sample(100, False)], 100))
        samples = [sample(100, True), sample(100.016, False), sample(100.1, True), sample(100.116, False)]
        gaps = moving_intervals([[0], [.2]], samples, 100)
        self.assertEqual(1, len(gaps))
        self.assertAlmostEqual(100, gaps[0], msg="the second burst was not shown for 100 ms")

    def test_movement_that_begins_and_ends_between_paints_cannot_disappear(self):
        samples = [sample(100, False), sample(100.030, True), sample(100.046, False)]
        gaps = moving_intervals([[0], [.150]], samples, 100)
        self.assertAlmostEqual(120, gaps[0])

    def test_an_update_stall_before_going_idle_is_still_charged(self):
        # The idle update completed after 100 ms; its work must not be backdated.
        gaps = moving_intervals([[0], [.120]], [sample(100, True), sample(100.100, False)], 100)
        self.assertAlmostEqual(100, gaps[0])

    def test_record_only_can_describe_a_stage_with_no_movement(self):
        result = stats([])
        self.assertEqual(0, result['count'])
        self.assertIsNone(result['max_ms'])

    def test_profile_reports_nested_methods_separately_and_gc_once_per_stage(self):
        columns = 'at stage method wall_ms cpu_ms allocated_objects props duplicate_props minor_gc major_gc gc_ms'.split()
        profile = dict(columns=columns, samples=[
            [10, 'combat', 'App#update', 20, 2, 100, 3, 1, 1, 0, 1],
            [10, 'combat', 'Scene#render', 18, 1, 90, 3, 1, 1, 0, 1]],
            decode_columns='at stage type bytes wall_ms cpu_ms allocated_objects'.split(),
            decodes=[[9.99, 'combat', 'state', 41000, 1, .9, 2000]], caveats='test',
            stages={'combat': dict(before=dict(minor_gc_count=2, major_gc_count=1, time=4, total_allocated_objects=500),
                after=dict(minor_gc_count=3, major_gc_count=1, time=5, total_allocated_objects=2600))})
        summary = frame_profile_summary(profile)
        combat = summary['stages']['combat']
        self.assertEqual(1, combat['gc']['minor_gc_count'])
        self.assertEqual(100, combat['methods']['App#update']['allocated_objects']['mean'])
        self.assertEqual(90, combat['methods']['Scene#render']['allocated_objects']['mean'])
        self.assertEqual(1, len(summary['slowest_updates'][0]['overlapping_decodes']))
        self.assertIsNone(frame_profile_summary(None))


if __name__ == "__main__":
    unittest.main()
