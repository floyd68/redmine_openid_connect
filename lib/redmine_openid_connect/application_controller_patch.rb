module RedmineOpenidConnect
  module ApplicationControllerPatch
    def require_login
      return super unless OicSession.enabled?

      if !User.current.logged?
        if request.get?
          url = request.original_url
        else
          url = url_for(:controller => params[:controller], :action => params[:action], :id => params[:id], :project_id => params[:project_id])
        end
        session[:remember_url] = url

        if OicSession.login_selector?
          redirect_to signin_path(:back_url => url)
        else
          redirect_to oic_login_url
        end

        return false
      end
      true
    end

    # set the current user _without_ resetting the session first
    def logged_user=(user)
      return super(user) unless OicSession.enabled?

      if user && user.is_a?(User)
        User.current = user
        start_user_session(user)
      else
        User.current = User.anonymous
      end
    end

    def session_expiration
      return super unless OicSession.enabled?

      if session[:user_id] && Rails.application.config.redmine_verify_sessions != false
        if session_expired? && !try_to_autologin
          set_localization(User.active.find_by_id(session[:user_id]))
          self.logged_user = nil
          flash[:error] = l(:error_session_expired)
          cookies.delete(autologin_cookie_name)
          require_login
        end
      end
    end
  end # ApplicationControllerPatch
end
