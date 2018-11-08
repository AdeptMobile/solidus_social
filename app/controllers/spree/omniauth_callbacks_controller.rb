class Spree::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include Spree::Core::ControllerHelpers::Common
  include Spree::Core::ControllerHelpers::Order
  include Spree::Core::ControllerHelpers::Auth
  include Spree::Core::ControllerHelpers::Store

  class << self
    def provides_callback_for(*providers)
      providers.each do |provider|
        define_method(provider) { omniauth_callback }
      end
    end
  end

  SolidusSocial::OAUTH_PROVIDERS.each do |provider|
    provides_callback_for provider[1].to_sym
  end

  def omniauth_callback
    if request.env['omniauth.error'].present?
      Rails.logger.warn("Error: " + auth_hash)
      flash[:error] = I18n.t('devise.omniauth_callbacks.failure', kind: auth_hash['provider'], reason: Spree.t(:user_was_not_valid))
      redirect_back_or_default(root_url)
      return
    end

    authentication = Spree::UserAuthentication.find_by_provider_and_uid(auth_hash['provider'], auth_hash['uid'])

    if authentication.present? and authentication.try(:user).present?
      flash[:notice] = I18n.t('devise.omniauth_callbacks.success', kind: auth_hash['provider'])

      return idme_path if auth_hash['provider'] == 'idme'

      sign_in_and_redirect :spree_user, authentication.user
    elsif spree_current_user
      spree_current_user.apply_omniauth(auth_hash)
      spree_current_user.save!
      flash[:notice] = I18n.t('devise.sessions.signed_in')

      return idme_path if auth_hash['provider'] == 'idme'

      redirect_back_or_default(account_url)
    else
      user = Spree::User.find_by_email(auth_hash['info']['email']) || Spree::User.new
      user.apply_omniauth(auth_hash)
      if user.save
        flash[:notice] = I18n.t('devise.omniauth_callbacks.success', kind: auth_hash['provider'])
        sign_in_and_redirect :spree_user, user
      else
        session[:omniauth] = auth_hash.except('extra')
        flash[:notice] = Spree.t(:one_more_step, kind: auth_hash['provider'].capitalize)

        return idme_path if auth_hash['provider'] == 'idme'

        redirect_to new_spree_user_registration_url
        return
      end
    end

    if current_order
      user = spree_current_user || authentication.user
      current_order.associate_user!(user)
      session[:guest_token] = nil
    end
  end

  def idme
    order = Spree::Order.find_by(guest_token: cookies.signed[:guest_token])
    return omniauth_callback if order.nil?

    order.is_military  = auth_hash.dig("info", "affiliation") == "Service Member"
    order.is_responder = auth_hash.dig("info", "affiliation") == "EMT"
    order.save

    flash[:notice] = "ID.me authentication successful! Promotion will be applied as you checkout."

    redirect_to cart_path
  end

  def idme_path
    redirect_to cart_path
  end

  def failure
    set_flash_message :alert, :failure, kind: failed_strategy.name.to_s.humanize, reason: failure_message
    redirect_to spree.login_path
  end

  def passthru
    render file: "#{Rails.root}/public/404", formats: [:html], status: 404, layout: false
  end

  def auth_hash
    request.env['omniauth.auth']
  end
end
