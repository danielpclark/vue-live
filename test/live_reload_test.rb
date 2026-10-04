# frozen_string_literal: true

require_relative 'test_helper'
require 'rack' # so LiveReload.rack3? reflects the installed Rack

class LiveReloadTest < Minitest::Test
  def test_snapshot_and_diff
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, live_reload: true)
      lr = VueLive::LiveReload.new(cfg)
      before = lr.snapshot
      assert_includes before.keys, 'App.vue'
      refute_includes before.keys, 'secret.txt'

      file = File.join(dir, 'app/vue/App.vue')
      File.utime(Time.now + 5, Time.now + 5, file)
      File.write(File.join(dir, 'app/vue/New.vue'), '<template><i/></template>')
      File.delete(File.join(dir, 'app/vue/Broken.vue'))
      assert_equal ['App.vue', 'Broken.vue', 'New.vue'], VueLive::LiveReload.diff(before, lr.snapshot)
    end
  end

  def test_stream_emits_change_events
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, live_reload: true, live_reload_interval: 0.05)
      stream = VueLive::LiveReload::Stream.new(cfg, VueLive::LiveReload.new(cfg))
      frames = []
      file = File.join(dir, 'app/vue/App.vue')
      touched = false
      catch(:done) do
        stream.each do |frame|
          frames << frame
          unless touched
            touched = true
            File.utime(Time.now + 5, Time.now + 5, file)
          end
          throw :done if frames.any? { |f| f.start_with?('event: change') }
        end
      end
      change = frames.find { |f| f.start_with?('event: change') }
      assert_equal "event: change\ndata: {\"files\":[\"App.vue\"]}\n\n", change
      assert_equal "retry: 1000\n\n", frames.first
    end
  end

  def test_streaming_body_writes_frames_and_stops_when_the_client_is_gone
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, live_reload: true, live_reload_interval: 0.05)
      body = VueLive::LiveReload::StreamingBody.new(cfg, VueLive::LiveReload.new(cfg))
      io = Class.new do
        attr_reader :written, :closed

        def initialize = @written = []

        def write(s)
          @written << s
          raise Errno::EPIPE if @written.size >= 3 # client disconnects after the change frame
        end

        def flush; end
        def close = @closed = true
      end.new
      File.utime(Time.now + 5, Time.now + 5, File.join(dir, 'app/vue/App.vue')) # happens before the baseline...
      Thread.new do
        sleep 0.1
        File.utime(Time.now + 9, Time.now + 9, File.join(dir, 'app/vue/nested/Child.vue'))
      end
      body.call(io)
      assert_equal "retry: 1000\n\n", io.written[0]
      assert_equal "event: change\ndata: {\"files\":[\"nested/Child.vue\"]}\n\n", io.written[2]
      assert io.closed
    end
  end

  def test_response_body_kind_matches_rack_version
    cfg = fresh_config(live_reload: true)
    _, headers, body = VueLive::LiveReload.new(cfg).stream_response
    assert_equal 'text/event-stream; charset=utf-8', headers['content-type']
    if VueLive::LiveReload.rack3?
      assert_kind_of VueLive::LiveReload::StreamingBody, body
    else
      assert_kind_of VueLive::LiveReload::Stream, body
    end
    refute VueLive::LiveReload::StreamingBody.method_defined?(:each), 'a Rack 3 streaming body must not respond to each'
    assert VueLive::LiveReload::StreamingBody.method_defined?(:call)
    assert VueLive::LiveReload::Stream.method_defined?(:each)
  end

  def test_stream_ends_after_max_lifetime
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, live_reload: true, live_reload_interval: 0.01)
      stream = VueLive::LiveReload::Stream.new(cfg, VueLive::LiveReload.new(cfg))
      stub_const = VueLive::LiveReload::Frames.const_get(:MAX_LIFETIME)
      VueLive::LiveReload::Frames.send(:remove_const, :MAX_LIFETIME)
      VueLive::LiveReload::Frames.const_set(:MAX_LIFETIME, 0.05)
      frames = stream.enum_for(:each).to_a
      assert_equal "retry: 1000\n\n", frames.first
    ensure
      VueLive::LiveReload::Frames.send(:remove_const, :MAX_LIFETIME)
      VueLive::LiveReload::Frames.const_set(:MAX_LIFETIME, stub_const)
    end
  end

  def test_defaults_follow_reload
    assert fresh_config(env: 'development').live_reload?
    refute fresh_config(env: 'production').live_reload?
    assert fresh_config(env: 'production', live_reload: true).live_reload?
  end
end
