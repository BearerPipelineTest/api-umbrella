require_relative "../../test_helper"

class Test::Proxy::Logging::TestIpGeocoding < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging
  parallelize_me!

  def setup
    super
    setup_server

    assert($config["geoip"]["maxmind_license_key"], "MAXMIND_LICENSE_KEY environment variable must be set with valid license for geoip tests to run")
  end

  def test_nginx_geoip_config
    nginx_config_path = File.join($config.fetch("root_dir"), "etc/nginx/router.conf")
    nginx_config = File.read(nginx_config_path)
    assert_match("geoip2", nginx_config)
  end

  def test_runs_auto_update_process
    processes = api_umbrella_process.processes
    assert_match(%r{^\[\+ \+\+\+ \+\+\+\] *geoip-auto-updater *uptime: \d+\w/\d+\w *pids: \d+/\d+$}, processes)
  end

  def test_ipv4_address
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "52.52.118.192",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "52.52.118.192",
      :country => "US",
      :region => "CA",
      :city => "San Jose",
      :lat => 37.3388,
      :lon => -121.8914,
    })
  end

  def test_ipv6_address
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "2001:4860:4860::8888",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "2001:4860:4860::8888",
      :country => "US",
      :region => nil,
      :city => nil,
      :lat => 37.751,
      :lon => -97.822,
    })
  end

  def test_ipv4_mapped_ipv6_address
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "0:0:0:0:0:ffff:3434:76c0",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "::ffff:52.52.118.192",
      :country => "US",
      :region => "CA",
      :city => "San Jose",
      :lat => 37.3388,
      :lon => -121.8914,
    })
  end

  def test_country_city_no_region
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "104.250.168.24",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "104.250.168.24",
      :country => "MC",
      :region => nil,
      :city => "Monte Carlo",
      :lat => 43.7333,
      :lon => 7.4167,
    })
  end

  def test_country_no_region_city
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "1.1.1.1",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "1.1.1.1",
      :country => "AU",
      :region => nil,
      :city => nil,
      :lat => -33.494,
      :lon => 143.2104,
    })
  end

  def test_no_country_region_city
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "127.0.0.1",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "127.0.0.1",
      :country => nil,
      :region => nil,
      :city => nil,
      :lat => nil,
      :lon => nil,
    })
  end

  def test_city_accent_chars
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "184.148.224.214",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "184.148.224.214",
      :country => "CA",
      :region => "QC",
      :city => "Trois-Rivières",
      :lat => 46.3633,
      :lon => -72.6143,
    })
  end

  def test_custom_country_asia
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "169.145.197.0",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "169.145.197.0",
      :country => "AP",
      :region => nil,
      :city => nil,
      :lat => 35.0,
      :lon => 105.0,
    })
  end

  def test_custom_country_europe
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "77.111.247.0",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "77.111.247.0",
      :country => "EU",
      :region => nil,
      :city => nil,
      :lat => 47.0,
      :lon => 8.0,
    })
  end

  def test_custom_country_anonymous_proxy
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "67.43.156.0",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "67.43.156.0",
      :country => "A1",
      :region => nil,
      :city => nil,
      :lat => nil,
      :lon => nil,
    })
  end

  def test_custom_country_satellite
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", log_http_options.deep_merge({
      :headers => {
        "X-Forwarded-For" => "196.201.135.0",
      },
    }))
    assert_response_code(200, response)

    record = wait_for_log(response)[:hit_source]
    assert_geocode(record, {
      :ip => "196.201.135.0",
      :country => "A2",
      :region => nil,
      :city => nil,
      :lat => nil,
      :lon => nil,
    })
  end

  private

  def assert_geocode(record, options)
    assert_geocode_log(record, options)
    if !options.fetch(:lat).nil? || !options.fetch(:lon).nil?
      assert_geocode_cache(record, options)
    end
  end

  def assert_geocode_log(record, options)
    assert_equal(options.fetch(:ip), record.fetch("request_ip"))
    if(options.fetch(:country).nil?)
      assert_nil(record["request_ip_country"])
      refute(record.key?("request_ip_country"))
    else
      assert_equal(options.fetch(:country), record.fetch("request_ip_country"))
    end
    if(options.fetch(:region).nil?)
      assert_nil(record["request_ip_region"])
      refute(record.key?("request_ip_region"))
    else
      assert_equal(options.fetch(:region), record.fetch("request_ip_region"))
    end
    if(options.fetch(:city).nil?)
      assert_nil(record["request_ip_city"])
      refute(record.key?("request_ip_city"))
    else
      assert_equal(options.fetch(:city), record.fetch("request_ip_city"))
    end
  end

  def assert_geocode_cache(record, options)
    id = Digest::SHA256.hexdigest("#{options.fetch(:country)}-#{options.fetch(:region)}-#{options.fetch(:city)}")
    locations = LogCityLocation.where(:_id => id).all
    assert_equal(1, locations.length)

    location = locations[0].attributes
    updated_at = location.delete("updated_at")
    coordinates = location["location"].delete("coordinates")

    assert_kind_of(Time, updated_at)
    assert_equal(2, coordinates.length)
    assert_in_delta(options.fetch(:lon), coordinates[0], 0.02)
    assert_in_delta(options.fetch(:lat), coordinates[1], 0.02)
    assert_equal({
      "_id" => id,
      "country" => options.fetch(:country),
      "region" => options.fetch(:region),
      "city" => options.fetch(:city),
      "location" => {
        "type" => "Point",
      },
    }.compact, location)
  end
end
