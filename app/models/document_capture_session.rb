class DocumentCaptureSession < ApplicationRecord
  include NonNullUuid

  belongs_to :user

  def self.create_by_user_id(user_id, analytics, hash = {})
    reuse_session = DocumentCaptureSession.find_by(user_id: user_id)
    if reuse_session
      reuse_session.reset(analytics)
    else
      reuse_session = DocumentCaptureSession.create(user_id: user_id)
    end
    reuse_session.assign_attributes(hash)
    reuse_session.save!
    reuse_session
  end

  def load_result
    EncryptedRedisStructStorage.load(result_id, type: DocumentCaptureSessionResult)
  end

  def store_result_from_response(doc_auth_response)
    EncryptedRedisStructStorage.store(
      DocumentCaptureSessionResult.new(
        id: generate_result_id,
        success: doc_auth_response.success?,
        pii: doc_auth_response.pii_from_doc,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
    save!
  end

  def load_doc_auth_async_result
    EncryptedRedisStructStorage.load(result_id, type: DocumentCaptureSessionAsyncResult)
  end

  def create_doc_auth_session
    EncryptedRedisStructStorage.store(
      DocumentCaptureSessionAsyncResult.new(
        id: generate_result_id,
        status: DocumentCaptureSessionAsyncResult::IN_PROGRESS,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
    save!
  end

  def store_doc_auth_result(result:, pii:)
    EncryptedRedisStructStorage.store(
      DocumentCaptureSessionAsyncResult.new(
        id: result_id,
        pii: pii,
        result: result,
        status: DocumentCaptureSessionAsyncResult::DONE,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
    save!
  end

  def load_proofing_result
    EncryptedRedisStructStorage.load(result_id, type: ProofingSessionAsyncResult)
  end

  def create_proofing_session
    EncryptedRedisStructStorage.store(
      ProofingSessionAsyncResult.new(
        id: generate_result_id,
        status: ProofingSessionAsyncResult::IN_PROGRESS,
        result: nil,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
    save!
  end

  def store_proofing_result(proofing_result)
    EncryptedRedisStructStorage.store(
      ProofingSessionAsyncResult.new(
        id: result_id,
        result: proofing_result,
        status: ProofingSessionAsyncResult::DONE,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
  end

  def expired?
    return true unless requested_at
    (requested_at + IdentityConfig.store.doc_capture_request_valid_for_minutes.minutes) <
      Time.zone.now
  end

  def reset(analytics)
    alert_if_session_in_use(analytics)

    self.result_id = nil
    self.requested_at = nil
    self.ial2_strict = nil
    self.issuer = nil
    self.cancelled_at = nil
  end

  def alert_if_session_in_use(analytics)
    return unless session_in_use?

    analytics.track_event(Analytics::DOCUMENT_CAPTURE_SESSION_OVERWRITTEN)
  end

  def session_in_use?
    self.created_at && !self.result_id && !self.cancelled_at
  end

  private

  def generate_result_id
    self.result_id = SecureRandom.uuid
  end
end
