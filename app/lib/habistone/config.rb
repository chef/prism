require "mixlib/config"

class Habistone
  module Config
    extend Mixlib::Config
    config_strict_mode true
    default :data_collector_url, "http://localhost/data-collector/v0/habitat/"
    default :data_collector_token, "93a49a4f2482c64126f7b6015e6b0f30284287ee4054ff8807fb63d9cbd1c506"
    default :supervisor_host, "localhost"
    default :supervisor_port, 9631
    default :habitat_ring_id, ""
    default :habitat_ring_alias, ""
    default :ssl_verification_enabled, true
  end
end
