# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/preferences"

class PreferencesTest < Minitest::Test
  def test_a_new_profile_does_not_inherit_another_profiles_sessions
    Dir.mktmpdir("burrow-profiles-") do |directory|
      first = Burrow::Client::Preferences.new(File.join(directory, "first.json"))
      first["sessions"]["local"] = "first-profile-token"
      first.save
      second = Burrow::Client::Preferences.new(File.join(directory, "second.json"))
      assert_empty second["sessions"]
      assert_equal "first-profile-token", Burrow::Client::Preferences.new(File.join(directory, "first.json"))["sessions"]["local"]
    end
  end
end
