CongressForms::App.controller do

  before do
    content_type :json

    if CORS_ALLOWED_DOMAINS.include? request.env['HTTP_ORIGIN'] or CORS_ALLOWED_DOMAINS.include? "*"
      response.headers['Access-Control-Allow-Origin'] = request.env['HTTP_ORIGIN']
    end
    response.headers['X-Backend-Hostname'] = Socket.gethostname.strip

    halt 401, {status: "error", message: "You must provide a valid debug key to access this endpoint."}.to_json unless params.include? "debug_key" and params["debug_key"] == DEBUG_KEY
  end

  before :'successful-fills-by-date', :'successful-fills-by-member/' do
    set_campaign_tag_params params
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

  get :'successful-fills-by-date', map: %r{/successful-fills-by-date/([\w]*)} do
    bio_id = params[:captures].first

    date_start = params.include?("date_start") ? Time.parse(params["date_start"]) : nil
    date_end = params.include?("date_end") ? Time.parse(params["date_end"]) : nil

    if bio_id.blank?
      @statuses = FillStatus
    else
      @statuses = CongressMember.bioguide(bio_id).fill_statuses
    end

    @statuses = @statuses.where('created_at > ?', date_start) unless date_start.nil?
    @statuses = @statuses.where('created_at < ?', date_end) unless date_end.nil?

    filter_by_campaign_tag

    @statuses.success.group_by_day(:created_at).count.to_json
  end

  get :'successful-fills-by-member/' do
    @statuses = FillStatus
    filter_by_campaign_tag

    member_id_mapping = {}
    member_hash = {}
    @statuses.success.each do |s|
      unless member_id_mapping.include? s.congress_member_id
        member_id_mapping[s.congress_member_id] = s.congress_member.bioguide_id
      end
      bioguide = member_id_mapping[s.congress_member_id]

      member_hash[bioguide] = 0 unless member_hash.include? bioguide
      member_hash[bioguide] += 1
    end

    member_hash.to_json
  end

  private

  define_method :set_campaign_tag_params do |params|
    if params.include? "campaign_tag"
      ct = CampaignTag.find_by_name(params["campaign_tag"])
      @ct_id = ct.nil? ? -1 : ct.id
    else
      @ct_id = nil
    end

    if @ct_id.nil?
      rake_ct = CampaignTag.find_by_name("rake")
      @rake_ct_id = rake_ct.nil? ? -1 : rake_ct.id
    end
  end

  define_method :filter_by_campaign_tag do
    if @ct_id.nil?
      @statuses = @statuses.where('campaign_tag_id != ? OR campaign_tag_id IS NULL', @rake_ct_id.to_s)
    else
      @statuses = @statuses.where(campaign_tag_id: @ct_id)
    end
  end
end
