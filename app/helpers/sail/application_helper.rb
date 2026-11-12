# frozen_string_literal: true

module Sail
  module ApplicationHelper # :nodoc:
    def main_app
      Rails.application.class.routes.url_helpers
    end

    def formatted_date(setting)
      DateTime.parse(setting.value).utc.strftime(Sail::ConstantCollection::INPUT_DATE_FORMAT)
    end

    def settings_page_path(page)
      settings_path(page: page, query: params[:query], order_field: params[:order_field])
    end

    def settings_container_class(number_of_pages)
      number_of_pages.zero? ? "empty" : ""
    end
  end
end
