require "rest-client"
require "json"
require "habistone/cli"
require "habistone/config"
require "habistone/member_config"

class Habistone
  def initialize
    @has_butterfly = false

    cli = Habistone::Cli.new
    cli.parse_options
    Habistone::Config.from_file(cli.config[:config_file]) if cli.config[:config_file]
    Habistone::Config.merge!(cli.config)
  end

  def print_configuration
    puts "Data collector url: #{Habistone::Config.data_collector_url}"
    puts "Habitat supervisor host: #{Habistone::Config.supervisor_host}"
    puts "Habitat supervisor port: #{Habistone::Config.supervisor_port}"
    puts "Habitat ring id: #{habitat_ring_id}"
    puts "Habitat ring alias: #{habitat_ring_alias}"
  end

  def run
    detect_butterfly_existence

    begin
      absorbed_findings = absorb
    rescue => e
      $stderr.puts "Unable to absorb data from ring: #{e.message}"
      return
    end

    refracted_data = refract(absorbed_findings)

    begin
      emit(refracted_data)
    rescue => e
      $stderr.puts "Unable to emit data: #{e.message}"
    end
  end

  def absorb
    handle_http_exceptions_for { RestClient.get("http://#{supervisor_host}:#{supervisor_port}/census").body }
  end

  def emit(message)
    data_collector = Habistone::Config.data_collector_url
    data_collector_token = Habistone::Config.data_collector_token
    handle_http_exceptions_for do
      RestClient::Request.execute(
        method: "post",
        url: data_collector,
        payload: message.to_json,
        headers: { "x-data-collector-token" => data_collector_token, "Content-Type" => "application/json" },
        verify_ssl: ssl_verify_mode
      )
    end
  end

  def refract(json)
    ring_census = JSON.parse(json)
    censuses = has_butterfly? ? ring_census["censuses"] : ring_census["census_list"]["censuses"]

    {
      ring_id: habitat_ring_id, #TODO: Get ring id from encyrption when encryption is on
      ring_alias: habitat_ring_alias,
      last_update: Time.now.strftime("%Y-%m-%dT%H:%M:%SZ"),
      service_groups: refract_service_groups(censuses),
    }
  end

  def refract_service_groups(censuses)
    censuses.map do |census, service_group|
      service_group_name = census

      {
        name: service_group_name,
        members: refract_members(service_group["population"]),
      }
    end
  end

  def refract_members(members)
    vis_members = Hash.new { |hash, key| hash[key] = Hash.new(&hash.default_proc) }
    members.each do |census_id, member|
      id = member["member_id"]

      vis_members[id]["census_id"]             = census_id
      vis_members[id]["member_id"]             = member["member_id"]
      vis_members[id]["org"]                   = member["org"]
      vis_members[id]["ip"]                    = member["ip"]
      vis_members[id]["leader"]                = member["leader"]
      vis_members[id]["follower"]              = member["follower"]
      vis_members[id]["hostname"]              = member["hostname"]
      vis_members[id]["status"]                = diffract_status(member)
      vis_members[id]["persistent"]            = member["persistent"]
      vis_members[id]["election_is_running"]   = member["election_is_running"]
      vis_members[id]["election_is_no_quorum"] = member["election_is_no_quorum"]
      vis_members[id]["election_is_finished"]  = member["election_is_finished"]
      vis_members[id]["initialized"]           = member["initialized"]
      vis_members[id]["port"]                  = member["port"]
      vis_members[id]["exposes"]               = member["exposes"]

      # The following keys are no longer part of the census payload
      # starting with Habitat v0.14. They should be removed in a future
      # release but are included here for backwards compatibility for
      # any users running Habitat v0.13 and earlier.
      vis_members[id]["vote"]        = member["vote"]
      vis_members[id]["election"]    = member["election"]
      vis_members[id]["needs_write"] = member["needs_write"]
      vis_members[id]["suitability"] = member["suitability"]
      vis_members[id]["incarnation"] = member["incarnation"]

      member_config = Habistone::MemberConfig.new(ip: member["ip"],
                                                  service: member["service"],
                                                  group: member["group"],
                                                  has_butterfly: has_butterfly?)
      vis_members[id]["configuration"] = member_config.get_config
    end

    vis_members
  end

  def diffract_status(member)
    if member["alive"]
      "alive"
    elsif member["suspect"]
      "suspect"
    elsif member["confirmed"]
      "confirmed"
    elsif member["detached"]
      "detached"
    else
      "unknown"
    end
  end

  private

  def handle_http_exceptions_for(&block)
    yield
  rescue RestClient::ExceptionWithResponse => e
    $stderr.puts "Error making HTTP request: #{e.class} - #{e.response.body}"
    raise
  rescue => e
    $stderr.puts "Error making HTTP request: #{e.class} - #{e.message}"
    raise
  end

  def ssl_verify_mode
    Habistone::Config.ssl_verification_enabled ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
  end

  def habitat_ring_id
    @ring_id ||= Habistone::Config.habitat_ring_id.empty? ? SecureRandom.uuid : Habistone::Config.habitat_ring_id
  end

  def habitat_ring_alias
    Habistone::Config.habitat_ring_alias.empty? ? "default" : Habistone::Config.habitat_ring_alias
  end

  def detect_butterfly_existence
    RestClient.get("http://#{supervisor_host}:#{supervisor_port}/butterfly")
  rescue RestClient::NotFound
    @has_butterfly = false
  else
    @has_butterfly = true
  end

  def has_butterfly?
    @has_butterfly
  end

  def supervisor_host
    Habistone::Config.supervisor_host
  end

  def supervisor_port
    Habistone::Config.supervisor_port
  end
end
