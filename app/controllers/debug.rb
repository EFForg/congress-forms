CongressForms::App.controller do

  before do
    content_type :json

    if CORS_ALLOWED_DOMAINS.include? request.env['HTTP_ORIGIN'] or CORS_ALLOWED_DOMAINS.include? "*"
      response.headers['Access-Control-Allow-Origin'] = request.env['HTTP_ORIGIN']
    end
    response.headers['X-Backend-Hostname'] = Socket.gethostname.strip

    halt 401, {status: "error", message: "You must provide a valid debug key to access this endpoint."}.to_json unless params.include? "debug_key" and params["debug_key"] == DEBUG_KEY
  end

  get :'recent-statuses-detailed/:bio_id' do
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
          status_hash = {status: s.status, error: dj.last_error, run_at: dj.run_at, dj_id: extra[:delayed_job_id]}
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
    return {status: "error", message: "You must provide a bio_id to retrieve the list of actions."}.to_json unless params.include? :bio_id

    bio_id = params[:bio_id]

    c = CongressMember.bioguide(bio_id)
    return {status: "error", message: "Congress member with provided bio id not found"}.to_json if c.nil?

    {last_updated: c.updated_at, actions: c.actions}.to_json
  end

  get :'list-congress-members' do
    CongressMember.all(order: :bioguide_id).to_json(only: :bioguide_id, methods: :form_domain_url)
  end

  get %r{/successful-fills-by-date/([\w]*)} do
    bio_id = params[:captures].first

    if params.include? "campaign_tag"
      ct = CampaignTag.find_by_name(params["campaign_tag"])
      ct_id = ct.nil? ? -1 : ct.id
    else
      ct_id = nil
    end

    if bio_id.blank?
      fills = ct_id.nil? ? FillStatus : FillStatus.where(campaign_tag_id: ct_id)
      fills.success.group_by_day(:created_at).count.to_json
    else
      statuses = CongressMember.bioguide(bio_id).fill_statuses
      statuses = statuses.where(campaign_tag_id: ct_id) unless ct_id.nil?

      statuses.success.group_by_day(:created_at).count.to_json
    end
  end

end
