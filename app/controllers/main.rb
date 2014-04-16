CongressForms::App.controller do
  get :index do
    render :index
  end

  before do
    if CORS_ALLOWED_DOMAINS.include? request.env['HTTP_ORIGIN'] or CORS_ALLOWED_DOMAINS.include? "*"
      response.headers['Access-Control-Allow-Origin'] = request.env['HTTP_ORIGIN']
    end
  end

  post :'retrieve-form-elements' do
    content_type :json
    return {status: "error", message: "You must provide bio_ids to retrieve form elements."}.to_json unless params.include? "bio_ids" and params["bio_ids"].is_a? Array

    bio_ids = params["bio_ids"]
    response = {}
    bio_ids.each do |bio_id|
      c = CongressMember.bioguide(bio_id)
      response[bio_id] = c.as_required_json unless c.nil?
    end
    response.to_json
  end

  fh = FillHash.new
  post :'fill-out-form' do
    content_type :json
    return {status: "error", message: "You must provide a bio_id, fields, and a uid to fill out form."}.to_json unless params.include? "bio_id" and params.include? "fields" and params.include? "uid"

    bio_id = params["bio_id"]
    fields = params["fields"]
    uid = params["uid"]

    c = CongressMember.bioguide(bio_id)
    return {status: "error", message: "Congress member with provided bio id not found"}.to_json if c.nil?

    handler = FillHandler.new(c)
    result = handler.fill fields, params["campaign_tag"]
    fh[uid] = handler if result[:status] == "captcha_needed"
    result.to_json
  end

  post :'fill-out-captcha' do
    content_type :json
    return {status: "error", message: "You must provide a uid and answer to fill out captcha."}.to_json unless params.include? "uid" and params.include? "answer"

    uid = params["uid"]
    answer = params["answer"]

    return {status: "error", message: "The unique id provided was not found."}.to_json unless fh.include? uid

    result = fh[uid].fill_captcha answer
    fh.delete(uid)
    result.to_json
  end

  get :'recent-fill-status/:bio_id' do
    content_type :json
    return {status: "error", message: "You must provide a bio_id to request the recent fill status."}.to_json unless params.include? :bio_id

    bio_id = params[:bio_id]
    c = CongressMember.bioguide(bio_id)

    c.recent_fill_status.to_json
  end

  get :'recent-fill-image/:bio_id' do
    content_type :json
    response.headers['Cache-Control'] = "no-cache"
    return {status: "error", message: "You must provide a bio_id to request the recent fill image."}.to_json unless params.include? :bio_id

    bio_id = params[:bio_id]
    c = CongressMember.bioguide(bio_id)
    redirect to('http://img.shields.io/badge/YAML-not%20found-red.svg') if c.nil?

    fill_status = c.recent_fill_status

    if [fill_status[:successes], fill_status[:errors], fill_status[:failures]].max == 0
      redirect to('http://img.shields.io/badge/not-tried-lightgray.svg'), 302
    else
      success_rate = fill_status[:successes].to_f / (fill_status[:successes] + fill_status[:errors] + fill_status[:failures])

      darkness = 0.8

      red = (1 - ([success_rate - 0.5, 0].max * 2)) * 255 * darkness
      green = [success_rate * 2, 1].min * 255 * darkness
      blue = 0

      color_hex = sprintf("%02X%02X%02X", red, green, blue)
      redirect to('http://img.shields.io/badge/success-' + (success_rate * 100).to_i.to_s + '%-' + color_hex + '.svg'), 302
    end
  end

  if DEBUG_ENDPOINTS
    get :'recent-statuses-detailed/:bio_id' do
      content_type :json
      return {status: "error", message: "You must provide a bio_id to request the most recent error."}.to_json unless params.include? :bio_id
      bio_id = params[:bio_id]

      c = CongressMember.bioguide(bio_id)
      return {status: "error", message: "Congress member with provided bio id not found."}.to_json if c.nil?

      statuses = c.recent_fill_statuses.order(:updated_at).reverse

      statuses_arr = []
      statuses.each do |s|
        if s.status == 'error' or s.status == 'failure'
          begin
            extra = YAML.load(s.extra)
            dj = Delayed::Job.find(extra[:delayed_job_id])
            status_hash = {status: s.status, error: dj.last_error, run_at: dj.run_at}
            status_hash[:screenshot] = extra[:screenshot] if extra.include? :screenshot
          rescue
            status_hash = {status: s.status, run_at: s.updated_at}
          end
        elsif s.status == 'success'
          status_hash = {status: s.status, run_at: s.updated_at}
        end
        statuses_arr.push(status_hash)
      end
      statuses_arr.to_json
    end

    get :'list-actions/:bio_id' do
      content_type :json
      return {status: "error", message: "You must provide a bio_id to retrieve the list of actions."}.to_json unless params.include? :bio_id

      bio_id = params[:bio_id]

      c = CongressMember.bioguide(bio_id)
      return {status: "error", message: "Congress member with provided bio id not found"}.to_json if c.nil?

      {last_updated: c.updated_at, actions: c.actions}.to_json
    end

    get :'list-congress-members' do
      content_type :json
      CongressMember.all(order: :bioguide_id).to_json(only: [:bioguide_id,:status], methods: :form_domain_url)
    end
  end
end
