require 'spec_helper'
require 'rake'

describe HealthController, type: :controller do
  describe "Hitting the health endpoint of Earthdata Search" do
    before :all do
      @delayed_job = DelayedJob.new
      @delayed_job.run_at = Time.now
      @delayed_job.created_at = Time.now
      @delayed_job.handler = 'test'

      @retrieval = Retrieval.new
      @retrieval.created_at = Time.now - 1.minute
    end

    # before :each do
    #   Dir.glob(Rails.root.join('tmp', "data_load_*")).each { |f| File.delete(f) }
    #   Dir.glob(Rails.root.join('tmp', "colormaps_load_*")).each { |f| File.delete(f) }
    #
    #   FileUtils.touch Rails.root.join('tmp', "data_load_#{Time.now.to_i}")
    #   FileUtils.touch Rails.root.join('tmp', "colormaps_load_#{Time.now.to_i}")
    #   allow(File).to receive(:ctime).with(Rails.root.join('README.md')).and_return(Time.now - 5.days)
    # end
    #
    # after :each do
    #   Dir.glob(Rails.root.join('tmp', "data_load_*")).each { |f| File.delete(f) }
    #   Dir.glob(Rails.root.join('tmp', "colormaps_load_*")).each { |f| File.delete(f) }
    # end

    context "when everything is up" do
      before :all do
        CronJobHistory.new(task_name: 'data:load:echo10', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'data:load:granules', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'data:load:tags', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'colormaps:load', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
      end

      after :all do
        CronJobHistory.delete_all
      end

      it "returns a json response indicating the system is ok" do

        get :index, format: 'json'

        json = JSON.parse response.body
        expect(json['edsc']).to eq({"ok?"=>true})
        expect(json['dependencies']['echo']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr_search']).to eq({"ok?"=>true})
        expect(json['dependencies']['urs']).to eq({"ok?"=>true})
        expect(json['dependencies']['opensearch']).to eq({"ok?"=>true})
        expect(json['dependencies']['browse_scaler']).to eq({"ok?"=>true})
        expect(json['background_jobs']['delayed_job']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_echo10']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_granules']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_tags']).to eq({"ok?"=>true})
        expect(json['background_jobs']['colormaps_load']).to eq({"ok?"=>true})
      end
    end

    context "when one of the dependencies is down" do
      before :all do
        CronJobHistory.new(task_name: 'data:load:echo10', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'data:load:granules', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'data:load:tags', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'colormaps:load', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
      end

      after :all do
        CronJobHistory.delete_all
      end

      it "returns a json response indicating edsc is not ok" do
        mock_client = Object.new
        allow(Echo::Client).to receive(:client_for_environment).and_return(mock_client)
        res = MockResponse.edsc_dependency({"availability"=>"NO"})
        expect(mock_client).to receive(:get_echo_availability).and_return(res)
        res = MockResponse.edsc_dependency({"ok?"=>true})
        expect(mock_client).to receive(:get_cmr_availability).and_return(res)
        expect(mock_client).to receive(:get_cmr_search_availability).and_return(res)
        expect(mock_client).to receive(:get_urs_availability).and_return(res)
        expect(mock_client).to receive(:get_opensearch_availability).and_return(res)
        res = MockResponse.edsc_dependency("hdf2jpeg is UP, image_magick is UP")
        expect(mock_client).to receive(:get_browse_scaler_availability).and_return(res)

        get :index, format: 'json'

        json = JSON.parse response.body
        expect(json['edsc']).to eq({"ok?"=>false})
        expect(json['dependencies']['echo']).to eq({"ok?"=>false, "error"=>"{\"availability\":\"NO\"}"})
        expect(json['dependencies']['cmr']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr_search']).to eq({"ok?"=>true})
        expect(json['dependencies']['urs']).to eq({"ok?"=>true})
        expect(json['dependencies']['opensearch']).to eq({"ok?"=>true})
        expect(json['dependencies']['browse_scaler']).to eq({"ok?"=>true})
        expect(json['background_jobs']['delayed_job']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_echo10']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_granules']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_tags']).to eq({"ok?"=>true})
        expect(json['background_jobs']['colormaps_load']).to eq({"ok?"=>true})
      end
    end

    context "when the SSL Certificate held by URS fails" do
      it "recovers from the exception and reports the failure" do
        mock_client = Object.new
        allow(Echo::Client).to receive(:client_for_environment).and_return(mock_client)
        res = MockResponse.edsc_dependency({"availability"=>"NO"})
        expect(mock_client).to receive(:get_echo_availability).and_return(res)
        expect(mock_client).to receive(:get_cmr_availability).and_return(res)
        expect(mock_client).to receive(:get_cmr_search_availability).and_return(res)
        res = MockResponse.connection_failed(nil)
        expect(mock_client).to receive(:get_urs_availability).and_return(res)
        expect(mock_client).to receive(:get_opensearch_availability).and_return(res)
        expect(mock_client).to receive(:get_browse_scaler_availability).and_return(res)

        get :index, format: 'json'
        json = JSON.parse response.body
        expect(json['dependencies']['urs']).to eq({"ok?"=>false, "error"=>"Response code is 500"})
      end
    end

    context "when one of the dependencies is down and the connection times out (nil body returns)" do
      before :all do
        CronJobHistory.new(task_name: 'data:load:echo10', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'data:load:granules', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'data:load:tags', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
        CronJobHistory.new(task_name: 'colormaps:load', last_run: Time.now - 1.minute, status: 'succeeded', host: 'host1').save!
      end

      after :all do
        CronJobHistory.delete_all
      end

      it "returns a json response indicating edsc is not ok" do
        mock_client = Object.new
        allow(Echo::Client).to receive(:client_for_environment).and_return(mock_client)

        res = MockResponse.edsc_dependency({"ok?"=>true, 'availability'=>'Available'})
        expect(mock_client).to receive(:get_echo_availability).and_return(res)
        expect(mock_client).to receive(:get_cmr_availability).and_return(res)
        expect(mock_client).to receive(:get_cmr_search_availability).and_return(res)
        expect(mock_client).to receive(:get_urs_availability).and_return(res)
        expect(mock_client).to receive(:get_opensearch_availability).and_return(res)
        res = MockResponse.connection_timeout(nil)
        expect(mock_client).to receive(:get_browse_scaler_availability).and_return(res)

        get :index, format: 'json'

        json = JSON.parse response.body
        expect(json['edsc']).to eq({"ok?"=>false})
        expect(json['dependencies']['echo']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr_search']).to eq({"ok?"=>true})
        expect(json['dependencies']['urs']).to eq({"ok?"=>true})
        expect(json['dependencies']['opensearch']).to eq({"ok?"=>true})
        expect(json['dependencies']['browse_scaler']).to eq({"ok?"=>false, "error"=>"Response code is 503"})
        expect(json['background_jobs']['delayed_job']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_echo10']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_granules']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_tags']).to eq({"ok?"=>true})
        expect(json['background_jobs']['colormaps_load']).to eq({"ok?"=>true})
      end
    end

    context "when one of the cron job hasn't been run for a while" do
      before :all do
        CronJobHistory.new(task_name: 'data:load:echo10', last_run: Time.now - 4.hours, status: 'succeeded', host: 'host1').save!
      end

      after :all do
        CronJobHistory.delete_all
      end

      it "returns a json response indicating edsc is not ok" do

        get :index, format: 'json'

        json = JSON.parse response.body
        expect(json['edsc']).to eq({"ok?"=>false})
        expect(json['dependencies']['echo']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr']).to eq({"ok?"=>true})
        expect(json['dependencies']['cmr_search']).to eq({"ok?"=>true})
        expect(json['dependencies']['urs']).to eq({"ok?"=>true})
        expect(json['dependencies']['opensearch']).to eq({"ok?"=>true})
        expect(json['dependencies']['browse_scaler']).to eq({"ok?"=>true})
        expect(json['background_jobs']['delayed_job']).to eq({"ok?"=>true})
        expect(json['background_jobs']['data_load_echo10'].to_json).to match(/\"ok\?\":false,\"error\":\"Cron job 'data:load:echo10' hasn't been run in the past 3\.0 hours/)
      end
    end

    context "when one of the cron job failed with an error" do
      before :all do
        CronJobHistory.new(task_name: 'data:load:echo10', last_run: Time.now, status: 'failed', message: 'error text', host: 'host1').save!
      end

      after :all do
        CronJobHistory.delete_all
      end

      it "returns a json response indicating edsc is not ok with the error message" do
        get :index, format: 'json'

        json = JSON.parse response.body
        expect(json['edsc']).to eq({"ok?"=>false})
        expect(json['background_jobs']['data_load_echo10'].to_json).to match(/\"ok\?\":false,\"error\":\"Cron job 'data:load:echo10' failed in last run at .* with message 'error text'\"/)
      end
    end
  end

end
