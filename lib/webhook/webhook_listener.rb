require 'net/http'
require 'rainbow'

Rainbow.enabled = Rails.application.config.colorize_logging || false

module Webhook
  class WebhookListener < Redmine::Hook::Listener
    def skip_webhooks(context)
      request = context[:request]
      if request.headers['X-Skip-Webhooks']
        return true
      end
      return false
    end

    def controller_issues_edit_after_save(context = {})
      return if skip_webhooks(context)
      journal = context[:journal]
      controller = context[:controller]
      issue = context[:issue]
      project = issue.project
      return unless project.module_enabled?('webhook')
      post(journal_to_json(issue, journal, controller))
    end

    private

    def journal_to_json(issue, journal, controller)
      {
          :payload => {
              :action => 'updated',
              :issue => Webhook::IssueWrapper.new(issue).to_hash,
              :journal => Webhook::JournalWrapper.new(journal).to_hash,
              :url => controller.issue_url(issue)
          }
      }.to_json
    end

    def post(request_body)
      Thread.start do
        begin
          url = Setting.plugin_webhook['url']
          if url.nil? || url == ''
            raise 'Url is not defined for webhook plugin'
          end
          url = URI.parse(url)
          headers = {
              'Content-Type' => 'application/jso n',
              'X-Redmine-Event' => 'Edit Issue',
          }

          log_debug("url: #{url.inspect} (#{URI.split(url.to_s)})")
          log_debug("headers: #{headers.inspect}")
          req = Net::HTTP::Post.new(url.request_uri, headers)
          req.body = request_body
          log_debug("req: #{req.inspect}")
          http = Net::HTTP.new(url.host, url.port)
          http.use_ssl = (url.scheme == "https")
          log_debug("http: #{http.inspect}")
          response = http.request(req)
          log_debug("response: #{response.inspect}")
        rescue => e
          log_error("req failed: #{e.to_s}")
        end
      end
    end

    def log_prefix
      @log_prefix ||= "[#{self.class.name.split("::").first}] "
    end

    def log_error(msg)
      Rails.logger.error(Rainbow(log_prefix).red.bright + msg)
    end

    def log_debug(msg)
      Rails.logger.debug(Rainbow(log_prefix).green.bright + msg)
    end
  end
end
