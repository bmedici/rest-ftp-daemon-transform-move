require 'streamio-ffmpeg'

module RestFtpDaemon::Transform
  class TransformFfmpeg < TransformBase
    FFMPEG_THREADS      = 2
    FFMPEG_ATTRIBUTES   = [:video_codec, :video_bitrate, :video_bitrate_tolerance, :frame_rate, :resolution, :aspect, :keyframe_interval, :x264_vprofile, :x264_preset, :audio_codec, :audio_bitrate, :audio_sample_rate, :audio_channels]

    # Task attributes
    def task_icon
      "facetime-video"
    end

    # Task operations
    def prepare stash
      # Init
      super
      @command = @config[:command]

      # Ensure command is available
      raise Task::TransformMissingBinary, "mp4split binary not defined" unless @command

      # Import command path
      FFMPEG.ffmpeg_binary = @config[:command]
      FFMPEG.ffprobe_binary = File.join(File.dirname(@config[:command]), "ffprobe")
      log_debug "FFMPEG binaries", {
        ffmpeg_binary: FFMPEG.ffmpeg_binary,
        ffprobe_binary: FFMPEG.ffprobe_binary,
        }

      # Ensure FFMPEG lib is available
      ffmpeg_check_binary :ffprobe_binary
      ffmpeg_check_binary :ffmpeg_binary

      # FIXME: only one source, otherwise  we don't know how to determine target name
      if stash.count>1
        raise RestFtpDaemon::SourceShouldBeUnique, "prepare: only one source can be matched for transformation"
      end
    end

    def process stash
      transform_each_input stash
    end

  protected

    def transform name, input, output
      # Read info about source file
      begin
        movie = FFMPEG::Movie.new(input.path_abs)
      rescue Errno::ENOENT => exception
        raise RestFtpDaemon::ErrorVideoNotFound, exception.message
      rescue StandardError => exception
        log_error "FFMPEG Error [#{exception.class}] : #{exception.message}"
        raise RestFtpDaemon::Transform::ErrorVideoError, exception.message
      else
        set_info :ffmpeg_size, movie.size
        set_info :ffmpeg_duration, movie.duration
        set_info :ffmpeg_resolution, movie.resolution
      end

      # Build options
      ffmpeg_options = {}
      FFMPEG_ATTRIBUTES.each do |name|
        # Skip if no value
        key = name.to_s
        next if @options[key].nil?

        # Grab this option and value frop @options
        ffmpeg_options[key]     = @options.delete(name)
      end
      ffmpeg_options[:custom]   = ffmpeg_options_from(@options[:custom])
      ffmpeg_options[:threads]  = FFMPEG_THREADS
      set_info :ffmpeg_options, ffmpeg_options

      # Build transcoder options
      transcoder_options = {validate: false}
      set_info :transcoder_options, transcoder_options

      # Announce context
      log_info "ffmpeg_command [#{FFMPEG.ffmpeg_binary}] [#{input.name}] > [#{output.name}]", ffmpeg_options

      # Run command
      movie.transcode(output.path_abs, ffmpeg_options, transcoder_options) do |ffmpeg_progress|
        # set_info :work, :ffmpeg_progress, ffmpeg_progress
        set_info INFO_TRANFER_PROGRESS, (100.0 * ffmpeg_progress).round(1)
        log_info "progress #{ffmpeg_progress}"
      end
    end

    def ffmpeg_options_from attributes
      # Ensure options ar in the correct format
      return [] unless attributes.is_a? Hash

      # Build the final array
      custom_parts = []
      attributes.each do |name, value|
        custom_parts << "-#{name}"
        custom_parts << value.to_s
      end

      # Return this
      return custom_parts
    end

    def ffmpeg_check_binary method
      # Get or evaluate the path which can raise a Errno::ENOENT
      path = FFMPEG.send method

      # Check that it returns something which exists on disk
      raise StandardError unless path && File.exist?(path)

    rescue StandardError, Errno::ENOENT => exception
      raise Transform::TransformMissingBinary, "missing ffmpeg binary: #{method}"
    end

  end
end