# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered! uncovered: 1

describe SecretsController do
  def create_global
    create_secret 'production/global/pod2/foo'
  end

  let(:secret) { create_secret 'production/foo/pod2/some_key' }
  let(:other_project) do
    Project.any_instance.stubs(:valid_repository_url).returns(true)
    Project.create!(name: 'Z', repository_url: 'Z')
  end
  let(:attributes) do
    {
      environment_permalink: 'production',
      project_permalink: 'foo',
      deploy_group_permalink: 'pod2',
      key: 'hi',
      value: 'secret',
      comment: 'hello',
      visible: "0",
      deprecated_at: "0"
    }
  end

  as_a_viewer do
    before { create_secret 'production/foo/group/bar' }

    unauthorized :get, :index
    unauthorized :get, :duplicates
    unauthorized :get, :new
    unauthorized :get, :show, id: 'production/foo/group/bar'
    unauthorized :patch, :update, id: 'production/foo/group/bar'
    unauthorized :delete, :destroy, id: 'production/foo/group/bar'
  end

  as_a_project_deployer do
    unauthorized :post, :create, secret: {
      environment_permalink: 'production',
      project_permalink: 'foo',
      deploy_group_permalink: 'group',
      key: 'bar'
    }

    describe '#index' do
      before { create_global }

      it 'renders template without secret values' do
        get :index
        assert_template :index
        assigns[:secrets].size.must_equal 1
        response.body.wont_include secret.value
      end

      it 'can filter by environment' do
        create_secret 'production/global/pod2/bar'
        get :index, params: {search: {environment_permalink: 'production'}}
        assert_template :index
        assigns[:secrets].map(&:first).sort.must_equal ["production/global/pod2/bar", "production/global/pod2/foo"]
      end

      it 'can filter by project' do
        create_secret 'production/foo-bar/pod2/bar'
        get :index, params: {search: {project_permalink: 'foo-bar'}}
        assert_template :index
        assigns[:secrets].map(&:first).must_equal ['production/foo-bar/pod2/bar']
      end

      it 'can filter by deploy group' do
        create_secret 'production/global/pod2/bar'
        get :index, params: {search: {deploy_group_permalink: 'pod2'}}
        assert_template :index
        assigns[:secrets].map(&:first).sort.must_equal ["production/global/pod2/bar", "production/global/pod2/foo"]
      end

      it 'can filter by key' do
        create_secret 'production/foo-bar/pod2/bar'
        get :index, params: {search: {key: 'bar'}}
        assert_template :index
        assigns[:secrets].map(&:first).must_equal ['production/foo-bar/pod2/bar']
      end

      it 'can filter by value_hashed' do
        other = create_secret 'production/global/pod2/baz'
        Samson::Secrets::Manager.write(
          other.id, value: 'other', user_id: 1, visible: true, comment: nil, deprecated_at: nil
        )
        get :index, params: {search: {value_hashed: Samson::Secrets::Manager.send(:hash_value, 'other')}}
        assert_template :index
        assigns[:secrets].map(&:first).must_equal [other.id]
      end

      it 'can filter by value_from' do
        other = create_secret 'production/global/pod2/baz'
        Samson::Secrets::Manager.write(
          other.id, value: 'other', user_id: 1, visible: true, comment: nil, deprecated_at: nil
        )
        Samson::Secrets::Manager.write(
          "#{other.id}-2", value: 'other', user_id: 1, visible: true, comment: nil, deprecated_at: nil
        )
        get :index, params: {search: {value_from: other.id}}
        assert_template :index
        assigns[:secrets].map(&:first).must_equal ["#{other.id}-2"]
      end

      it 'raises when vault server is broken' do
        Samson::Secrets::Manager.expects(:lookup_cache).raises(Samson::Secrets::BackendError.new('this is my error'))
        get :index
        assert flash[:error]
      end
    end

    describe "#duplicates" do
      it "renders" do
        a = 'production/global/pod2/foo'
        create_secret a
        b = 'production/global/pod2/bar'
        create_secret b
        create_secret 'production/global/pod2/baz', value: 'other'

        get :duplicates
        assert_response :success

        assigns(:groups).map { |_, v| v.map(&:first) }.must_equal [[a, b]]
      end
    end

    describe "#new" do
      let(:checked) { "checked=\"checked\"" }

      it "renders since we do not know what project the user is planing to create for" do
        get :new
        assert_template :show
      end

      it "renders pre-filled visible false values from params of last form" do
        get :new, params: {secret: {visible: '0'}}
        assert_response :success
        response.body.wont_include "checked=\"checked\""
      end

      it "renders pre-filled visible true values from params of last form" do
        get :new, params: {secret: {visible: '0'}}
        assert_response :success
        response.body.wont_include checked
      end

      it "renders pre-filled visible false values from params of last form with project set" do
        get :new, params: {secret: {visible: '0', project_permalink: 'foo'}}
        assert_response :success
        response.body.wont_include "checked=\"checked\""
      end
    end

    describe '#show' do
      it 'renders for local secret as project-admin' do
        get :show, params: {id: secret}
        assert_template :show
      end

      it 'hides invisible secrets' do
        get :show, params: {id: secret}
        refute assigns(:secret).fetch(:value)
        response.body.wont_include secret.value
      end

      it 'shows visible secrets' do
        secret.update_column(:visible, true)
        get :show, params: {id: secret}
        assert_template :show
        response.body.must_include secret.value
      end

      it 'renders with unfound users' do
        secret.update_column(:updater_id, 32232323)
        get :show, params: {id: secret}
        assert_template :show
        response.body.must_include "Unknown user id"
      end
    end

    describe '#update' do
      it "is unauthrized" do
        put :update, params: {id: secret, secret: {value: 'xxx'}}
        assert_response :unauthorized
      end
    end

    describe "#destroy" do
      it "is unauthorized" do
        delete :destroy, params: {id: secret.id}
        assert_response :unauthorized
      end
    end
  end

  as_a_deployer do
    describe '#index' do
      it 'renders template' do
        get :index
        assert_template :index
      end
    end
  end

  as_a_project_admin do
    describe '#create' do
      it 'creates a secret' do
        post :create, params: {secret: attributes.merge(visible: 'false')}
        assert flash[:notice]
        assert_redirected_to secrets_path
        secret = Samson::Secrets::DbBackend::Secret.find('production/foo/pod2/hi')
        secret.updater_id.must_equal user.id
        secret.creator_id.must_equal user.id
        secret.visible.must_equal false
        secret.comment.must_equal 'hello'
        secret.deprecated_at.must_equal nil
      end

      it 'writes nil to deprecated_at to make vault work and not store strange values' do
        attributes[:deprecated_at] = "0"
        Samson::Secrets::Manager.expects(:write).with { |_, data| data.fetch(:deprecated_at).must_equal nil }
        post :create, params: {secret: attributes}
      end

      it 'does not override an existing secret' do
        attributes[:key] = secret.id.split('/').last
        post :create, params: {secret: attributes}
        refute flash[:notice]
        assert flash[:error]
        assert_template :show
        secret.reload.value.must_equal 'MY-SECRET'
      end

      it "redirects to new form when user wants to create another secret" do
        post :create, params: {secret: attributes, commit: SecretsController::ADD_MORE}
        flash[:notice].wont_be_nil
        redirect_params = attributes.except(:value).merge(visible: false, deprecated_at: nil)
        assert_redirected_to "/secrets/new?#{{secret: redirect_params}.to_query}"
      end

      it 'renders and sets the flash when invalid' do
        attributes[:key] = ''
        post :create, params: {secret: attributes}
        assert flash[:error]
        assert_template :show
      end

      it "is not authorized to create global secrets" do
        attributes[:project_permalink] = 'global'
        post :create, params: {secret: attributes}
        assert_response :unauthorized
      end

      it "does not log secret values" do
        Rails.logger.stubs(:info)
        Rails.logger.expects(:info).with { |message| message.include?("\"value\"=>\"[FILTERED]\"") }
        post :create, params: {secret: attributes}
      end

      it "does not store windows newlines in the backend" do
        attributes[:value] = "foo\r\nbar\r\nbaz"
        post :create, params: {secret: attributes}
        Samson::Secrets::DbBackend::Secret.find('production/foo/pod2/hi').value.must_equal "foo\nbar\nbaz"
      end
    end

    describe '#update' do
      def attributes
        @attributes ||= super.except(*Samson::Secrets::Manager::ID_PARTS)
      end

      def do_update
        patch :update, params: {id: secret.id, secret: attributes}
      end

      before { secret }

      it 'updates' do
        do_update
        flash[:notice].wont_be_nil
        assert_redirected_to secrets_path
        secret.reload
        secret.updater_id.must_equal user.id
        secret.creator_id.must_equal users(:admin).id
      end

      it 'backfills value when user is only updating comment' do
        attributes[:value] = ""
        do_update
        assert_redirected_to secrets_path
        secret.reload
        secret.value.must_equal "MY-SECRET"
        secret.comment.must_equal 'hello'
      end

      it "does not allow backfills when user tries to make hidden visible" do
        attributes[:value] = ""
        attributes[:visible] = "1"
        do_update
        assert_template :show
        assert flash[:error]
      end

      it "does not allow backfills when secret was visible since value should have been visible" do
        attributes[:value] = ""
        Samson::Secrets::Manager.write(
          secret.id, visible: true, value: "secret", user_id: user.id, comment: "", deprecated_at: nil
        )
        do_update
        assert_template :show
        assert flash[:error]
      end

      it 'fails to update when write fails' do
        Samson::Secrets::Manager.expects(:write).returns(false)
        do_update
        assert_template :show
        assert flash[:error]
      end

      it "is does not allow updating key" do
        attributes[:key] = 'bar'
        do_update
        assert_redirected_to secrets_path
        secret.reload.id.must_equal 'production/foo/pod2/some_key'
      end

      describe 'duplicate secret key values' do
        def do_update(extras = {})
          secret
          create_secret 'production/foo/pod2/other_key', value: 'do-not-duplicate'
          put :update, params: {id: secret, secret: attributes.merge(value: 'do-not-duplicate').merge(extras)}
        end

        it 'shows validation error on duplicate secret' do
          do_update

          assert_response :success
          assert flash[:error]
        end

        it 'changes value placeholder and makes it required on duplicate secret' do
          do_update

          assert_response :ok
          assert_select '#secret_value[required=?]', 'required'
          assert_select '#secret_value[placeholder]', count: 0
        end

        it 'allows duplicate secret if allow_duplicates is true' do
          do_update(allow_duplicates: '1')

          assert_redirected_to secrets_path
        end

        it 'shows validation error when not checking allow_duplicates' do
          do_update(allow_duplicates: '0')

          assert_response :success
          assert flash[:error]
        end

        it 'allows editing of an already existing duplicate value' do
          secret
          create_secret 'production/foo/pod2/other_key', value: secret.value

          put :update, params: {id: secret, secret: {comment: 'hello', visible: '0'}}

          assert_redirected_to secrets_path
        end
      end

      describe 'showing a not owned project' do
        let(:secret) { create_secret "production/#{other_project.permalink}/foo/xxx" }

        it "is not allowed" do
          do_update
          assert_response :unauthorized
        end
      end

      describe 'global' do
        let(:secret) { create_global }

        it "is unauthrized" do
          do_update
          assert_response :unauthorized
        end
      end
    end

    describe "#destroy" do
      it "deletes project secret" do
        delete :destroy, params: {id: secret}
        assert_redirected_to "/secrets"
        Samson::Secrets::DbBackend::Secret.exists?(secret.id).must_equal(false)
      end

      it "deletes secret that already was deleted so we can cleanup after a partial deletetion failure" do
        delete :destroy, params: {id: "a/foo/c/d"}
        assert_redirected_to "/secrets"
      end

      it "responds ok to xhr" do
        delete :destroy, params: {id: secret}, xhr: true
        assert_response :success
        Samson::Secrets::DbBackend::Secret.exists?(secret.id).must_equal(false)
      end

      it "is unauthorized for global" do
        delete :destroy, params: {id: create_global}
        assert_response :unauthorized
      end
    end
  end

  as_an_admin do
    let(:secret) { create_global }

    describe '#create' do
      before do
        post :create, params: {secret: attributes}
      end

      it 'redirects and sets the flash' do
        assert_redirected_to secrets_path
        flash[:notice].wont_be_nil
      end
    end

    describe '#show' do
      it "renders" do
        get :show, params: {id: secret.id}
        assert_template :show
      end

      it "renders with unknown project" do
        secret.update_column(:id, 'oops/bar')
        get :show, params: {id: secret.id}
        assert_template :show
      end
    end

    describe '#update' do
      it "updates" do
        put :update, params: {id: secret, secret: attributes.except(*Samson::Secrets::Manager::ID_PARTS)}
        assert_redirected_to secrets_path
      end
    end

    describe '#destroy' do
      it 'deletes global secret' do
        delete :destroy, params: {id: secret.id}
        assert_redirected_to "/secrets"
        Samson::Secrets::DbBackend::Secret.exists?(secret.id).must_equal(false)
      end

      it "works with unknown project" do
        secret.update_column(:id, 'oops/bar')
        delete :destroy, params: {id: secret.id}
        assert_redirected_to "/secrets"
        Samson::Secrets::DbBackend::Secret.exists?(secret.id).must_equal(false)
      end
    end
  end
end
