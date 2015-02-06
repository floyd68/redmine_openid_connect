module OpenidConnect
  module AccountControllerPatch
    def self.included(base)
      base.send(:include, InstanceMethods)

      base.class_eval do
        # Add before filters and stuff here
        alias_method_chain :logout, :openid_connect
      end
    end
  end # AccountControllerPatch

  module InstanceMethods
    def logout_with_openid_connect
      return logout_without_openid_connect unless OpenidConnect.enabled?

      logout_user

      redirect_to OpenidConnect.logout_session_uri
    end

    def create_or_login_the_account
      data = OpenidConnect.get_user_info

      # Check if there's already an existing user
      user = User.find_by_login(data[:user_name])

      if user.nil?
        user = User.new

        user.login = data[:user_name]

        user.assign_attributes({
          agency_id: Agency.first.id,
          firstname: data[:given_name],
          lastname: data[:family_name],
          mail: data[:email],
          mail_notification: 'only_my_events',
          last_login_on: Time.now
        })

        if user.save
          self.logged_user = user

          successful_authentication(user)
        else
          # Add error handling here
        end
      else
        self.logged_user = user

        successful_authentication(user)
      end # if user.nil?
    end

    false
  end # InstanceMethods
end