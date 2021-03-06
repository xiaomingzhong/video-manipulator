class ProgressCalculator
  attr_reader :video, :format, :format_options, :new_progress

  def initialize(video, format, format_options, new_progress)
    @video = video
    @format = format
    @format_options = format_options
    @new_progress = new_progress
  end

  def update!
    update_progress_data if shoud_update?
  end

  private

  def update_progress_data
    # Had to use atomic set operation here since normal update
    # has been setting file_processing to false while processing still was not finished
    step_metadata.set(progress: new_progress.to_f)
    video.set(progress: calculate_overall_progress.to_f)
    notify_about_progress
  end

  def step
    format_options[:processing_metadata][:step]
  end

  def step_metadata
    video.processing_metadatas.find_or_create_by!(step: step) do |pm|
      pm.format = format
    end
  end

  def diff
    new_progress.to_f - step_metadata.progress.to_f
  end

  def shoud_update?
    # Update this value only each 10th percent or when processing is finished
    diff >= 0.1 || (new_progress.to_i == 1)
  end

  def steps_count
    # Normalize step + 1
    # Effects steps + effects.count
    # Watermark step + 1
    # Read video metadata step + 1
    # Generate thumbnails step + 1
    count = ::VideoUploader::OBLIGATORY_STEPS.count + video.effects.count
    count += 1 if video.watermark_image.path.present?
    count += 1 if video.needs_thumbnails?
    count
  end

  def calculate_overall_progress
    video.processing_metadatas.sum(:progress) / steps_count
  end

  def notify_about_progress
    ::ActionCable.server.broadcast(
      'notifications_channel',
      progress_payload
    )
  end

  def progress_payload
    ::CableData::VideoProcessing::ProgressSerializer.new(video).as_json
  end
end
