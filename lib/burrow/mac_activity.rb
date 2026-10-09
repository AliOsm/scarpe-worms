# frozen_string_literal: true

module Burrow
  # The Ruby controller/host have no NSWindow of their own. Tell macOS when
  # their timers serve a live match instead of letting background heuristics
  # coalesce them. Release the hint when idle; allow normal display/system sleep.
  class MacActivity
    USER_INITIATED_ALLOWING_SLEEP = 0x00ffffff & ~(1 << 20)
    LATENCY_CRITICAL = 0xff00000000
    attr_reader :error, :activations

    def initialize(reason, precise: true, backend: nil)
      @reason, @backend = reason, backend
      @options = USER_INITIATED_ALLOWING_SLEEP | (precise ? LATENCY_CRITICAL : 0)
      @supported = !!backend || (RUBY_PLATFORM.include?("darwin") && ENV["BURROW_MAC_ACTIVITY"] != "0")
      @activations = 0
    end

    def active? = !!@token

    def active=(wanted)
      return if !@supported || @error || wanted == active?
      @backend ||= Cocoa.new
      if wanted
        @token = @backend.begin_activity(@options, @reason)
        raise "macOS did not return an activity token" unless @token
        @activations += 1
      else
        token, @token = @token, nil
        @backend.end_activity(token)
      end
    rescue LoadError, StandardError => exception
      @error = "#{exception.class}: #{exception.message}"
      warn "macOS activity unavailable: #{@error}"
    end

    def close = (self.active = false)

    def report
      {supported: @supported, active: active?, activations: activations, error: error,
        allows_idle_sleep: true, precise_timers: (@options & LATENCY_CRITICAL) != 0}
    end

    # Small typed Objective-C bridge using Ruby's bundled Fiddle. The explicit
    # msgSend signatures are required by the Apple silicon ABI (no varargs).
    class Cocoa
      def initialize
        require "fiddle"
        @foundation = Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
        @objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
        pointer, void = Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOID
        @get_class = function("objc_getClass", [pointer], pointer)
        @selector = function("sel_registerName", [pointer], pointer)
        @send = function("objc_msgSend", [pointer, pointer], pointer)
        @send_arg = function("objc_msgSend", [pointer, pointer, pointer], pointer)
        @send_options = function("objc_msgSend", [pointer, pointer, Fiddle::TYPE_LONG_LONG, pointer], pointer)
        @send_void = function("objc_msgSend", [pointer, pointer, pointer], void)
        @retain = function("objc_retain", [pointer], pointer)
        @release = function("objc_release", [pointer], void)
        @push_pool = function("objc_autoreleasePoolPush", [], pointer)
        @pop_pool = function("objc_autoreleasePoolPop", [pointer], void)
        @begin_selector = @selector.call("beginActivityWithOptions:reason:")
        @end_selector = @selector.call("endActivity:")
        @string_selector = @selector.call("stringWithUTF8String:")
        @string_class = @get_class.call("NSString")
        @process_info = @send.call(@get_class.call("NSProcessInfo"), @selector.call("processInfo"))
      end

      def begin_activity(options, reason)
        pool = @push_pool.call
        text = @send_arg.call(@string_class, @string_selector, reason.encode(Encoding::UTF_8))
        token = @send_options.call(@process_info, @begin_selector, options, text)
        token.null? ? nil : @retain.call(token)
      ensure
        @pop_pool.call(pool) if pool
      end

      def end_activity(token)
        pool = @push_pool.call
        @send_void.call(@process_info, @end_selector, token)
      ensure
        @release.call(token)
        @pop_pool.call(pool) if pool
      end

      private

      def function(name, arguments, result)
        Fiddle::Function.new(@objc[name], arguments, result)
      end
    end
  end
end
