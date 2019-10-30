require 'net/http'

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
          Rails.logger.debug "[WEBHOOK] url: #{url.inspect} (#{URI.split(url.to_s)})"
          Rails.logger.debug "[WEBHOOK] headers: #{headers.inspect}"
          req = Net::HTTP::Post.new(url.request_uri, headers)
          req.body = request_body
          Rails.logger.debug "[WEBHOOK] req: #{req.inspect}"
          http = Net::HTTP.new(url.host, url.port)
          http.use_ssl = (url.scheme == "https")
          Rails.logger.debug "[WEBHOOK] http: #{http.inspect}"
          response = http.request(req)
          Rails.logger.debug "[WEBHOOK] response: #{response.inspect}"
        rescue => e
          Rails.logger.error e
          Rails.logger.debug "[WEBHOOK] req failed: #{e.inspect}"
        end
      end
    end
  end
end
