module Idv
  # Ignore instance variable assumption on @user_locked_out :reek:InstanceVariableAssumption
  class SendPhoneConfirmationOtp
    def initialize(user:, idv_session:)
      @user = user
      @idv_session = idv_session
    end

    def call
      otp_rate_limiter.reset_count_and_otp_last_sent_at if user.decorate.no_longer_locked_out?

      return too_many_otp_sends_response if rate_limit_exceeded?
      otp_rate_limiter.increment
      return too_many_otp_sends_response if rate_limit_exceeded?

      send_otp
      FormResponse.new(success: true, errors: {}, extra: extra_analytics_attributes)
    end

    def user_locked_out?
      @user_locked_out
    end

    private

    attr_reader :user, :idv_session

    delegate :user_phone_confirmation_session, to: :idv_session
    delegate :phone, :code, :delivery_method, to: :user_phone_confirmation_session

    def too_many_otp_sends_response
      FormResponse.new(
        success: false,
        errors: {},
        extra: extra_analytics_attributes,
      )
    end

    def rate_limit_exceeded?
      if otp_rate_limiter.exceeded_otp_send_limit?
        otp_rate_limiter.lock_out_user
        return @user_locked_out = true
      end
      false
    end

    def otp_rate_limiter
      @otp_rate_limiter ||= OtpRateLimiter.new(
        user: user,
        phone: phone,
      )
    end

    def send_otp
      idv_session.user_phone_confirmation_session = user_phone_confirmation_session.regenerate_otp
      Telephony.send_confirmation_otp(
        otp: code,
        to: phone,
        expiration: Devise.direct_otp_valid_for.to_i / 60,
        channel: delivery_method,
      )
      Db::ProofingCost::AddUserProofingCost.call(user.id, :phone_otp)
    end

    def extra_analytics_attributes
      parsed_phone = Phonelib.parse(phone)
      {
        otp_delivery_preference: delivery_method,
        country_code: parsed_phone.country,
        area_code: parsed_phone.area_code,
        rate_limit_exceeded: rate_limit_exceeded?,
      }
    end
  end
end
