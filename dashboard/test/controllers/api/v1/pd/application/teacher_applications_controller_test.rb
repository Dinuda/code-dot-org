require 'test_helper'

module Api::V1::Pd::Application
  class TeacherApplicationsControllerTest < ::ActionController::TestCase
    include Pd::Application::ApplicationConstants
    include Pd::Application::ActiveApplicationModels

    self.use_transactional_test_case = true

    setup_all do
      @test_params = {
        form_data: build(TEACHER_APPLICATION_HASH_FACTORY)
      }

      @applicant = create :teacher

      @program_manager = create :program_manager
      @partner = @program_manager.regional_partners.first
      @application = create TEACHER_APPLICATION_FACTORY, regional_partner: @partner
    end

    setup do
      Pd::Application::TeacherApplicationMailer.stubs(:confirmation).returns(
        mock {|mail| mail.stubs(:deliver_now)}
      )

      Pd::Application::TeacherApplicationMailer.stubs(:principal_approval).returns(
        mock {|mail| mail.stubs(:deliver_now)}
      )
    end

    test_redirect_to_sign_in_for :create
    test_user_gets_response_for :create, user: :student, params: -> {@test_params}, response: :forbidden
    test_user_gets_response_for :create, user: :teacher, params: -> {@test_params}, response: :success

    test_redirect_to_sign_in_for :update, params: -> {{id: @application.id}}
    test_user_gets_response_for :update, user: :student, params: -> {{id: @application.id}}, response: :forbidden

    test_user_gets_response_for :update,
      name: 'a teacher cannot update an application they do not own',
      user: :teacher,
      params: -> {{id: @application.id}},
      response: :forbidden

    test_user_gets_response_for :update,
      name: 'a teacher can update an application they own',
      user:  -> {User.find_by(id: @application.user_id)},
      params: -> {{id: @application.id}},
      response: :success

    test_user_gets_response_for :change_principal_approval_requirement,
                                name: 'program managers can set change_principal_approval_requirement for applications they own',
                                user: -> {@program_manager},
                                params: -> {{id: @application.id, principal_approval_not_required: true}},
                                response: :success

    test_user_gets_response_for :change_principal_approval_requirement,
                                name: 'program managers cannot set change_principal_approval_requirement for applications they do not own',
                                user: :program_manager,
                                params: -> {{id: @application.id}},
                                response: :forbidden

    test_user_gets_response_for :send_principal_approval,
      name: 'program managers can send_principal_approval for applications they own',
      user: -> {@program_manager},
      params: -> {{id: @application.id}},
      response: :success

    test_user_gets_response_for :send_principal_approval,
      name: 'program managers can not send_principal_approval for applications they do not own',
      user: :program_manager,
      params: -> {{id: @application.id}},
      response: :forbidden

    test 'sends email on successful create' do
      Pd::Application::TeacherApplicationMailer.expects(:confirmation).
        with(instance_of(TEACHER_APPLICATION_CLASS)).
        returns(mock {|mail| mail.expects(:deliver_now)})

      sign_in @applicant

      put :create, params: @test_params
      assert_response :success
    end

    test 'does not send principal approval email on successful create if RP has selective principal approval' do
      Pd::Application::TeacherApplicationMailer.expects(:confirmation).
        with(instance_of(TEACHER_APPLICATION_CLASS)).
        returns(mock {|mail| mail.expects(:deliver_now)})

      PRINCIPAL_APPROVAL_APPLICATION_CLASS.expects(:create_placeholder_and_send_mail).never

      regional_partner = create :regional_partner, applications_principal_approval: RegionalPartner::ALL_REQUIRE_APPROVAL

      TEACHER_APPLICATION_CLASS.any_instance.stubs(:regional_partner).returns(regional_partner)

      sign_in @applicant

      put :create, params: @test_params
      assert_response :success
    end

    test 'does not send confirmation mail on unsuccessful create' do
      Pd::Application::TeacherApplicationMailer.expects(:principal_approval).never
      Pd::Application::TeacherApplicationMailer.expects(:confirmation).never
      PRINCIPAL_APPROVAL_APPLICATION_CLASS.expects(:create_placeholder_and_send_mail).never

      sign_in @applicant

      put :create, params: {form_data: {firstName: ''}}
      assert_response :bad_request
    end

    test 'submit is idempotent' do
      create TEACHER_APPLICATION_FACTORY, user: @applicant

      sign_in @applicant
      assert_no_difference "#{TEACHER_APPLICATION_CLASS.name}.count" do
        put :create, params: {form_data: @test_params}
      end
    end

    test 'creating an application on an existing form renders conflict' do
      sign_in @applicant
      application = create TEACHER_APPLICATION_FACTORY, user: @applicant
      post :create, params:  {
        id: application.id
      }
      assert_response :conflict
    end

    test 'updating an application with an error renders bad_request' do
      sign_in @applicant
      application = create TEACHER_APPLICATION_FACTORY, user: @applicant
      put :update, params: {id: application.id, form_data: @test_params, application_year: nil}

      assert_response :bad_request
    end

    test 'updates user school info on successful create' do
      TEACHER_APPLICATION_CLASS.any_instance.expects(:update_user_school_info!)

      sign_in @applicant
      put :create, params: @test_params
    end

    test 'does not send emails or autoscore on successful create if application status is incomplete' do
      Pd::Application::TeacherApplicationMailer.expects(:confirmation).never
      Pd::Application::TeacherApplicationMailer.expects(:principal_approval).never

      sign_in @applicant
      put :create, params: {form_data_hash: @test_params, status: 'incomplete'}
      refute TEACHER_APPLICATION_CLASS.last.response_scores
      assert_response :created
    end

    test 'updates course hours, autoscores, and queues email once application is submitted' do
      application_hash = build :pd_teacher_application_hash_common, :csp,
                               cs_how_many_minutes: 45,
                               cs_how_many_days_per_week: 5,
                               cs_how_many_weeks_per_year: 30
      application = create :pd_teacher_application, form_data_hash: application_hash, user: @applicant, status: 'incomplete'

      Pd::Application::TeacherApplicationMailer.expects(:confirmation).once.
        with(instance_of(TEACHER_APPLICATION_CLASS)).
        returns(mock {|mail| mail.expects(:deliver_now)})
      Pd::Application::TeacherApplicationMailer.expects(:principal_approval).once.
        with(instance_of(TEACHER_APPLICATION_CLASS)).
        returns(mock {|mail| mail.expects(:deliver_now)})

      sign_in @applicant
      put :update, params: {id: application.id, form_data: application_hash, status: 'unreviewed'}
      assert_equal 112, TEACHER_APPLICATION_CLASS.last.sanitize_form_data_hash[:cs_total_course_hours]
      assert JSON.parse(TEACHER_APPLICATION_CLASS.last.response_scores).any?
      assert_response :ok
    end

    test 'can submit an empty form if application is incomplete' do
      sign_in @applicant
      put :create, params: {status: 'incomplete'}

      assert_equal 'incomplete', TEACHER_APPLICATION_CLASS.last.status
      assert_response :created
    end

    test 'updating an application with empty form data updates appropriate fields' do
      sign_in @applicant
      application = create TEACHER_APPLICATION_FACTORY, user: @applicant
      original_data = application.form_data_hash
      original_school_info = @applicant.school_info

      # Keep cs_total_course_hours because it is calculated on create or update
      put :update, params: {id: application.id, status: 'incomplete', form_data: {"cs_total_course_hours": 80}}
      application.reload
      refute_equal original_data, application.form_data_hash
      assert_nil application.course
      assert_nil application.form_data_hash[:cs_total_course_hours]
      assert_equal original_school_info, @applicant.school_info
      assert_response :ok
    end

    test 'change_principal_approval_requirement can set principal_approval_not_required to true' do
      sign_in @program_manager
      refute @application.principal_approval_not_required

      post :change_principal_approval_requirement, params: {id: @application.id, principal_approval_not_required: true}
      assert @application.reload.principal_approval_not_required
    end

    test 'change_principal_approval_requirement can set principal_approval_not_required to false' do
      application = create TEACHER_APPLICATION_FACTORY, regional_partner: @partner
      sign_in @program_manager
      application.update!(principal_approval_not_required: true)

      assert_equal true, application.principal_approval_not_required
      post :change_principal_approval_requirement, params: {id: application.id, principal_approval_not_required: false}
      refute application.reload.principal_approval_not_required
    end

    test 'send_principal_approval queues up an email if none exist' do
      sign_in @program_manager
      assert_creates Pd::Application::Email do
        post :send_principal_approval, params: {id: @application.id}
        assert_response :success
      end
      email = Pd::Application::Email.last
      assert_equal @application, email.application
      assert_equal 'principal_approval', email.email_type
    end

    test 'send_principal_approval does nothing if an email has already been sent' do
      Pd::Application::Email.create!(
        application: @application,
        application_status: @application.status,
        email_type: 'principal_approval',
        to: 'principal@ex.net',
        created_at: Time.now,
        sent_at: Time.now
      )

      sign_in @program_manager
      assert_does_not_create Pd::Application::Email do
        post :send_principal_approval, params: {id: @application.id}
        assert_response :success
      end
    end
  end
end
