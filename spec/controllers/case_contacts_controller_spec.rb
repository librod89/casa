require "rails_helper"

RSpec.describe CaseContactsController, type: :controller do
  let(:organization) { build(:casa_org) }
  let(:volunteer) { create(:volunteer, :with_casa_cases, casa_org: organization) }
  let(:admin) { create(:casa_admin) }
  let(:supervisor) { create(:supervisor) }
  let(:case_id) { volunteer.casa_cases.first.id }
  let(:params) { {case_contact: {casa_case_id: case_id}} }
  let!(:contact_type_group_one) do
    create(:contact_type_group, casa_org: organization).tap do |group|
      create(:contact_type, contact_type_group: group, name: "Attorney")
    end
  end
  let!(:contact_type_group_two) do
    create(:contact_type_group, casa_org: organization).tap do |group|
      create(:contact_type, contact_type_group: group, name: "Therapist")
    end
  end

  before do
    travel_to Date.new(2021, 1, 1)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(volunteer)
  end

  describe "GET new" do
    context "when the case has specific contact types assigned" do
      before do
        casa_case = volunteer.casa_cases.first
        casa_case.contact_types = contact_type_group_one.contact_types
        casa_case.save
      end

      it "only assigns that contact types groups to @current_organization_groups" do
        get :new, params: params
        expect(assigns(:current_organization_groups)).to eq([contact_type_group_one])
      end
    end

    context "when the case does not have specific contact types assigned" do
      it "assigns all the organizations contact type groups to @current_organization_groups" do
        get :new, params: params
        expect(assigns(:current_organization_groups)).to eq([contact_type_group_one, contact_type_group_two])
      end

      it "calls contact_types_alphabetically" do
        allow(controller).to receive(:current_organization).and_return(organization)
        allow(organization).to receive_message_chain(
          :contact_type_groups,
          :joins,
          :where,
          :alphabetically,
          :uniq
        )

        expect(organization).to receive_message_chain(
          :contact_type_groups,
          :joins,
          :where,
          :alphabetically,
          :uniq
        )

        get :new, params: {case_contact: {casa_case_id: case_id}}
      end
    end
  end

  describe "POST #create" do
    context "with valid params" do
      let(:params) { build(:case_contact).attributes }

      it "assigns @case_contact" do
        post :create, params: {case_contact: params}, format: :js
        expect(assigns(:case_contact)).to be_an_instance_of(CaseContact)
      end

      it "assigns @casa_cases" do
        post :create, params: {case_contact: params}, format: :js
        expect(assigns(:casa_cases)).to eq(volunteer.casa_cases)
      end

      it "assigns @current_organization_groups" do
        post :create, params: {case_contact: params}, format: :js
        expect(assigns(:current_organization_groups)).to eq(organization.contact_type_groups)
      end

      context "when a casa case was not selected" do
        it "does not create a new case contact" do
          expect {
            post :create, params: {case_contact: params}, format: :js
          }.not_to change(CaseContact, :count)
        end

        it "renders the new template" do
          post :create, params: {case_contact: params}, format: :js
          expect(flash[:alert]).to eq("At least one case must be selected")
          expect(response).to render_template("new")
        end
      end

      context "when a casa case is selected" do
        let(:params) { build(:case_contact).attributes.merge("casa_case_id" => [volunteer.casa_cases.first.id.to_s]) }

        it "assigns @selected_cases" do
          post :create, params: {case_contact: params}, format: :js
          expect(assigns(:selected_cases)).to eq(CasaCase.where(id: volunteer.casa_cases.first.id))
        end

        it "creates a new case contact for each selected case" do
          starter_counts = volunteer.casa_cases.map { |cc| cc.case_contacts.count }

          expect(starter_counts).to eq([0, 0])

          post :create, params: {case_contact: params}, format: :js
          after_counts = volunteer.casa_cases.map { |cc| cc.case_contacts.count }

          expect(after_counts).to eq([1, 0])
        end

        it "renders the casa case show template" do
          post :create, params: {case_contact: params}, format: :js
          expect(flash[:notice]).to include("Case contact was successfully created.")
          expect(response).to redirect_to casa_case_path(CaseContact.last.casa_case)
        end

        it "renders a random thank you message" do
          post :create, params: {case_contact: params}, format: :js
          expect(
            (1..8).map { |n| "#{I18n.t("create", scope: "case_contact")} #{I18n.t("thank_you_#{n}", scope: "case_contact")}" }
          ).to include(flash[:notice])
        end
      end
    end

    context "with invalid params" do
      let(:params) { build(:case_contact).attributes }

      it "assigns @case_contact" do
        post :create, params: {case_contact: params}, format: :js
        expect(assigns(:case_contact)).to be_an_instance_of(CaseContact)
      end

      it "does not create a new case contact" do
        expect {
          post :create, params: {case_contact: params}, format: :js
        }.not_to change(CaseContact, :count)
      end

      it "renders the new template" do
        post :create, params: {case_contact: params}, format: :js
        expect(response).to render_template("new")
      end
    end
  end

  describe "DELETE destroy" do
    let(:case_contact) { create(:case_contact, creator: volunteer) }

    context "when logged in as admin" do
      let(:case_contact) { create(:case_contact, creator: volunteer) }
      before do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin)
        request.env["HTTP_REFERER"] = "http://example.com"
      end

      context ".destroy" do
        before { delete :destroy, params: {id: case_contact.id} }
        it { expect(response).to have_http_status(:redirect) }
        it { expect(case_contact.reload.deleted?).to be_truthy }
        it { expect(flash[:notice]).to eq("Contact is successfully deleted.") }
      end

      context ".restore" do
        before do
          case_contact.destroy
          post :restore, params: {id: case_contact.id}
        end

        it { expect(response).to have_http_status(:redirect) }
        it { expect(case_contact.reload.deleted?).to be_falsey }
        it { expect(flash[:notice]).to eq("Contact is successfully restored.") }
      end
    end

    context "when logged in as supervisor" do
      before do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(supervisor)
      end

      context ".destroy" do
        before { delete :destroy, params: {id: case_contact.id} }
        it { expect(response).to have_http_status(:redirect) }
        it { expect(case_contact.reload.deleted?).to be_falsey }
        it { expect(flash[:notice]).to eq("Sorry, you are not authorized to perform this action.") }
      end

      context ".restore" do
        before do
          case_contact.destroy
          post :restore, params: {id: case_contact.id}
        end

        it { expect(response).to have_http_status(:redirect) }
        it { expect(case_contact.reload.deleted?).to be_truthy }
        it { expect(flash[:notice]).to eq("Sorry, you are not authorized to perform this action.") }
      end
    end

    context "when logged in as volunteer" do
      before do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(volunteer)
      end

      context ".destroy" do
        before { delete :destroy, params: {id: case_contact.id} }
        it { expect(response).to have_http_status(:redirect) }
        it { expect(case_contact.reload.deleted?).to be_falsey }
        it { expect(flash[:notice]).to eq("Sorry, you are not authorized to perform this action.") }
      end

      context ".restore" do
        before do
          case_contact.destroy
          post :restore, params: {id: case_contact.id}
        end

        it { expect(response).to have_http_status(:redirect) }
        it { expect(case_contact.reload.deleted?).to be_truthy }
        it { expect(flash[:notice]).to eq("Sorry, you are not authorized to perform this action.") }
      end
    end
  end
end
