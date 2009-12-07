class CheckoutsController < Spree::BaseController
  include Spree::Checkout::Hooks
  include ActionView::Helpers::NumberHelper # Needed for JS usable rate information
  before_filter :load_data
  before_filter :set_state

  resource_controller :singleton
  actions :show, :edit, :update
  belongs_to :order

  ssl_required :update, :edit
    
  # GET /checkout is invalid but we'll assume a bookmark or user error and just redirect to edit (assuming checkout is still in progress)           
  show.wants.html { redirect_to edit_object_url }
  
  edit.before :edit_hooks  
  delivery.edit_hook :load_available_methods 
    
  update.before :update_before
  update.after :update_after
  
  update do
    flash nil
    success.wants.html do
      if @checkout.completed_at 
        complete_order
        redirect_to order_url(@order, {:checkout_complete => true}) and next
      else
        render 'edit'
      end
    end
  end
    
  private
  def update_before
    # call the edit hooks for the current step in case we experience validation failure and need to edit again      
    edit_hooks
    @checkout.enable_validation_group(@checkout.state.to_sym)
  end
  
  def update_after
    update_hooks
    next_step
  end

  # Calls edit hooks registered for the current step  
  def edit_hooks  
    edit_hook @checkout.state.to_sym 
  end
  # Calls update hooks registered for the current step  
  def update_hooks
    update_hook @checkout.state.to_sym 
  end
    
  def object
    return @object if @object
    @object = parent_object.checkout
    unless params[:checkout] and params[:checkout][:coupon_code]
      # do not create these defaults if we're merely updating coupon code, otherwise we'll have a validation error
      if user = parent_object.user || current_user
        @object.shipment.address ||= user.ship_address
        @object.bill_address     ||= user.bill_address
      end
      @object.shipment.address ||= Address.default
      @object.bill_address     ||= Address.default
      @object.creditcard       ||= Creditcard.new(:month => Date.today.month, :year => Date.today.year)
    end
    @object
  end

  def load_data
    @countries = Country.find(:all).sort
    @shipping_countries = parent_object.shipping_countries.sort
    if current_user && current_user.bill_address
      default_country = current_user.bill_address.country
    else
      default_country = Country.find Spree::Config[:default_country_id]
    end
    @states = default_country.states.sort                                

    # prevent editing of a complete checkout  
    redirect_to order_url(parent_object) if parent_object.checkout_complete
  end

  def set_state
    object.state = params[:step] || Checkout.state_machine.initial_state(nil).name
  end
  
  def next_step      
    @checkout.next!
    # call edit hooks for this next step since we're going to just render it (instead of issuing a redirect)
    edit_hooks
  end
  
  def load_available_methods        
    @available_methods = rate_hash
    @checkout.shipment.shipping_method_id ||= @available_methods.first[:id]
  end

  def complete_order
    flash[:notice] = t('order_processed_successfully')
  end
  
  def rate_hash
    fake_shipment = Shipment.new :order => @order, :address => @order.ship_address
    @order.shipping_methods.collect do |ship_method|
      fake_shipment.shipping_method = ship_method
      { :id => ship_method.id,
        :name => ship_method.name,
        :rate => number_to_currency(ship_method.calculate_cost(fake_shipment)) }
    end
  end
end