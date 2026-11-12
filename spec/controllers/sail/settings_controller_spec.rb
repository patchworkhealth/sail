# frozen_string_literal: true

describe Sail::SettingsController, type: :controller do
  routes { Sail::Engine.routes }
  before do
    Rails.cache.delete("setting_get_setting")
    allow(Rails.logger).to receive(:info)
  end

  describe "GET index" do
    subject { get :index, params: params }

    let(:params) { { page: "1" } }

    before do
      Sail::Setting.create!(name: :setting, cast_type: :string, value: :something)
    end

    it "queries settings with pagination" do
      expect(Sail::Setting).to receive(:paginated).with("1", 20)
      subject
      expect(response).to have_http_status(:ok)
    end

    it "sets eTag in response headers" do
      subject
      expect(response.headers["ETag"]).to_not be_nil
    end

    it "sets the number of pages" do
      subject
      expect(controller.instance_variable_get(:@number_of_pages)).to eq(1)
    end

    context "when passing a query" do
      let(:params) { { query: "test" } }

      it "invokes proper scope with query" do
        expect(Sail::Setting).to receive(:by_name).with("test").and_call_original
        subject
      end
    end

    context "when passing a field for ordering" do
      let(:params) { { order_field: "updated_at" } }
      let!(:setting) { Sail::Setting.create!(name: :setting_2, cast_type: :string, value: :something_else, updated_at: 2.days.ago) }

      it "invokes ordered_by properly" do
        subject
        expect(controller.instance_variable_get(:@settings).last.name).to eq(setting.name)
      end
    end
  end

  describe "PUT update" do
    subject { put :update, params: { name: setting.name, value: new_value, cast_type: setting.cast_type }, format: :js }

    let!(:setting) { Sail::Setting.create(name: :setting, cast_type: :string, value: "old value") }
    let(:new_value) { "new value" }

    it "updates setting value" do
      expect(setting.value).to eq("old value")
      subject
      expect(response).to have_http_status(:ok)
      expect(setting.reload.value).to eq("new value")
    end

    it "logs change information" do
      expect(Rails.logger).to receive(:info).with(/.* \[Sail\] Update setting='setting' value='new value' author_user_id=1/)
      subject
    end

    context "when setting is boolean" do
      let!(:setting) { Sail::Setting.create(name: :setting, cast_type: :boolean, value: "false") }
      let(:new_value) { "on" }

      it "updates setting value" do
        expect(setting.value).to eq("false")
        subject
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("true")
      end
    end

    context "when format is JSON" do
      subject { put :update, params: { name: setting.name, value: new_value, cast_type: setting.cast_type }, format: :json }

      it "updates setting value" do
        expect(setting.value).to eq("old value")
        subject
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("new value")
      end

      context "when update fails" do
        before do
          allow(Sail::Setting).to receive(:set).and_return([nil, false])
        end

        it "returns http status conflict" do
          subject
          expect(response).to have_http_status(:conflict)
        end

        it "does not log changes" do
          expect(Rails.logger).to_not receive(:info).with(/.* \[Sail\] Update setting='setting' value='new value' author_user_id=1/)
          subject
        end
      end
    end
  end

  describe "GET index pagination" do
    render_views

    let(:per_page) { Sail::ConstantCollection::SETTINGS_PER_PAGE }

    def create_settings(range)
      range.each { |i| Sail::Setting.create!(name: "setting_#{i}", cast_type: :string, value: "value") }
    end

    def page_link_texts
      Nokogiri::HTML(response.body).css("#pagination .page-links a").map { |link| link.text.strip }.reject(&:empty?)
    end

    around do |example|
      original_store = ActionController::Base.cache_store
      original_perform_caching = ActionController::Base.perform_caching
      ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
      ActionController::Base.perform_caching = true
      example.run
    ensure
      ActionController::Base.cache_store = original_store
      ActionController::Base.perform_caching = original_perform_caching
    end

    before { create_settings(0...per_page) }

    context "when a setting is added on a later page" do
      it "changes the ETag of the first page" do
        get :index
        first_etag = response.headers["ETag"]

        create_settings(per_page..per_page)
        get :index

        expect(response.headers["ETag"]).not_to eq(first_etag)
      end

      it "links to the new page straight away" do
        get :index
        expect(page_link_texts).to eq(["1"])

        create_settings(per_page..per_page)
        get :index

        expect(page_link_texts).to eq(%w[1 2])
      end
    end

    context "when a setting is removed from a later page" do
      before { create_settings(per_page..per_page) }

      it "stops linking to the empty page straight away" do
        get :index
        expect(page_link_texts).to eq(%w[1 2])

        Sail::Setting.find_by(name: "setting_#{per_page}").destroy
        get :index

        expect(page_link_texts).to eq(["1"])
      end
    end

    context "when a setting on a later page is updated" do
      before { create_settings(per_page..per_page) }

      it "changes the ETag of the first page" do
        get :index
        first_etag = response.headers["ETag"]

        Sail::Setting.find_by(name: "setting_#{per_page}").update!(value: "new value")
        get :index

        expect(response.headers["ETag"]).not_to eq(first_etag)
      end
    end

    context "when sorting by a field" do
      before { create_settings(per_page..per_page) }

      it "keeps the sort field in the page links" do
        get :index, params: { order_field: "updated_at" }

        hrefs = Nokogiri::HTML(response.body).css("#pagination .page-links a").map { |link| link.attr("href") }

        expect(hrefs).to all(include("order_field=updated_at"))
      end
    end
  end

  describe "GET show" do
    subject { get :show, params: params, format: :json }

    let!(:setting) { Sail::Setting.create(name: :setting, cast_type: :string, value: "some value") }
    let(:params) { { name: setting.name } }

    it "returns setting value" do
      subject
      body = JSON.parse(response.body)
      expect(body["value"]).to eq(setting.value)
    end

    it "returns 200 status" do
      subject
      expect(response).to have_http_status(:ok)
    end

    it "responds in json format" do
      subject

      type = Rails::VERSION::MAJOR < 6 ? response.content_type : response.media_type

      expect(type).to eq("application/json")
    end
  end

  describe "GET switcher" do
    subject { get :switcher, params: params, format: :json }

    let!(:throttle) { Sail::Setting.create(name: :throttle, cast_type: :throttle, value: "50.0") }
    let(:params) { { positive: :positive, negative: :negative, throttled_by: :throttle } }

    before do
      Rails.cache.delete("setting_get_positive")
      Rails.cache.delete("setting_get_negative")
      Rails.cache.delete("setting_get_throttle")
      Sail::Setting.create!(name: :positive, cast_type: :string, value: "I'm the primary!")
      Sail::Setting.create!(name: :negative, cast_type: :integer, value: "7")
      allow_any_instance_of(Sail::Types::Throttle).to receive(:rand).and_return(random_value)
    end

    context "when random value is smaller than throttle" do
      let(:random_value) { 0.25 }

      it "returns ok status" do
        subject
        expect(response).to have_http_status(:ok)
      end

      it "returns value of positive setting" do
        subject

        body = JSON.parse(response.body)
        expect(body["value"]).to eq("I'm the primary!")
      end
    end

    context "when random value is greater than throttle" do
      let(:random_value) { 0.75 }

      it "returns ok status" do
        subject
        expect(response).to have_http_status(:ok)
      end

      it "returns value of negative setting" do
        subject

        body = JSON.parse(response.body)
        expect(body["value"]).to eq(7)
      end
    end

    context "when throttle setting is of the wrong type" do
      let!(:throttle) { Sail::Setting.create!(name: :throttle, cast_type: :boolean, value: "true") }
      let(:random_value) { 0.75 }

      it "returns bad request" do
        subject
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when throttle setting does not exist" do
      let!(:throttle) { Sail::Setting.create!(name: :wrong_name, cast_type: :boolean, value: "true") }
      let(:random_value) { 0.75 }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT reset" do
    subject { put :reset, params: { name: setting.name }, format: :js }

    let!(:setting) { Sail::Setting.create(name: :setting, cast_type: :string, value: "old value") }
    let(:file_contents) { { "setting" => { "value" => "new value" } } }

    before do
      allow(File).to receive(:exist?)
      allow(Sail::Setting).to receive(:config_file_path).and_return("./config/sail.yml")
      allow(File).to receive(:exist?).with("./config/sail.yml").and_return(true)
      allow(YAML).to receive(:load_file).with("./config/sail.yml").and_return(file_contents)
    end

    it "resets setting value" do
      expect(Sail::Setting).to receive(:reset).with("setting").and_call_original
      subject
      expect(response).to have_http_status(:ok)
      expect(setting.reload.value).to eq("new value")
    end

    it "logs change information" do
      expect(Rails.logger).to receive(:info).with(/.* \[Sail\] Reset setting='setting' value='new value' author_user_id=1/)
      subject
    end

    context "when update fails" do
      before do
        allow(Sail::Setting).to receive(:set).and_return([nil, false])
      end

      it "does not log changes" do
        expect(Rails.logger).to_not receive(:info).with(/.* \[Sail\] Update setting='setting' value='new value' author_user_id=1/)
        subject
      end
    end
  end
end
