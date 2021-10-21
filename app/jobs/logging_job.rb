class LoggingJob < ApplicationJob
  def perform(job_id:, sleep_duration: 10)
    Rails.logger.info(
      {
        host: Socket.gethostname,
        job_id: job_id,
        pid: Process.pid,
        thread_id: Thread.current.object_id,
      }.to_json,
    )

    sleep(sleep_duration)
  end
end
