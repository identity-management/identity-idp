class NewPhoneForm
  include ActiveModel::Model
  include FormPhoneValidator
  include OtpDeliveryPreferenceValidator

  BLOCKED_PHONE_TYPES = [
    :premium_rate,
    :shared_cost,
  ].freeze

  validates :otp_delivery_preference, inclusion: { in: %w[voice sms] }

  validate :validate_not_voip
  validate :validate_not_duplicate
  validate :validate_not_premium_rate

  attr_accessor :phone, :international_code, :otp_delivery_preference,
                :otp_make_default_number

  def initialize(user)
    self.user = user
    self.otp_delivery_preference = user.otp_delivery_preference
    self.otp_make_default_number = false
  end

  def submit(params)
    ingest_submitted_params(params)

    success = valid?
    self.phone = submitted_phone unless success

    FormResponse.new(success: success, errors: errors, extra: extra_analytics_attributes)
  end

  def delivery_preference_sms?
    true
  end

  def delivery_preference_voice?
    false
  end

  def already_has_phone?
    user.phone_configurations.map(&:phone).include?(phone)
  end

  private

  attr_accessor :user, :submitted_phone

  def ingest_phone_number(params)
    self.international_code = params[:international_code]
    self.submitted_phone = params[:phone]
    self.phone = PhoneFormatter.format(
      submitted_phone,
      country_code: international_code,
    )
  end

  def extra_analytics_attributes
    {
      otp_delivery_preference: otp_delivery_preference,
      phone_type: @phone_info&.type, # comes from pinpoint API
      types: parsed_phone.types, # comes from Phonelib gem
      carrier: @phone_info&.carrier,
      country_code: parsed_phone.country,
      area_code: parsed_phone.area_code,
      pii_like_keypaths: [[:errors, :phone], [:error_details, :phone]],
    }.tap do |extra|
      extra[:redacted_phone] = @redacted_phone if @redacted_phone
    end
  end

  def validate_not_voip
    return if phone.blank? || !IdentityConfig.store.voip_check

    @phone_info = Telephony.phone_info(phone)

    return unless IdentityConfig.store.voip_block

    if @phone_info.type == :voip &&
       !FeatureManagement.voip_allowed_phones.include?(parsed_phone.e164)
      errors.add(:phone, I18n.t('errors.messages.voip_phone'))
    elsif @phone_info.error
      errors.add(:phone, I18n.t('errors.messages.voip_check_error'))
    end
  rescue Aws::Pinpoint::Errors::BadRequestException
    errors.add(:phone, :improbable_phone)
    @redacted_phone = redact(phone)
  end

  def validate_not_duplicate
    current_user_phones = user.phone_configurations.map do |phone_configuration|
      PhoneFormatter.format(phone_configuration.phone)
    end

    return unless current_user_phones.include?(phone)
    errors.add(:phone, I18n.t('errors.messages.phone_duplicate'))
  end

  def validate_not_premium_rate
    if (parsed_phone.types & BLOCKED_PHONE_TYPES).present?
      errors.add(:phone, I18n.t('errors.messages.premium_rate_phone'))
    end
  end

  def parsed_phone
    @parsed_phone ||= Phonelib.parse(phone)
  end

  def ingest_submitted_params(params)
    ingest_phone_number(params)

    delivery_prefs = params[:otp_delivery_preference]
    default_prefs = params[:otp_make_default_number]

    self.otp_delivery_preference = delivery_prefs if delivery_prefs
    self.otp_make_default_number = true if default_prefs
  end

  def redact(phone)
    phone.gsub(/[a-z]/i, 'X').gsub(/\d/i, '#')
  end

  def confirmed_phone?
    false
  end
end
