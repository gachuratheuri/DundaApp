defmodule Dunda.Security.URLTest do
  use ExUnit.Case, async: false

  setup do
    previous_hosts = Application.get_env(:dunda, :scraper_allowed_hosts)
    previous_requirement = Application.get_env(:dunda, :scraper_require_allowlist)
    Application.put_env(:dunda, :scraper_allowed_hosts, [])
    Application.put_env(:dunda, :scraper_require_allowlist, false)

    on_exit(fn ->
      Application.put_env(:dunda, :scraper_allowed_hosts, previous_hosts)
      Application.put_env(:dunda, :scraper_require_allowlist, previous_requirement)
    end)

    :ok
  end

  test "accepts only HTTPS URLs and rejects obvious SSRF targets" do
    assert Dunda.Security.URL.safe_https_url?("https://example.com/events")
    refute Dunda.Security.URL.safe_https_url?("http://example.com/events")
    refute Dunda.Security.URL.safe_https_url?("https://localhost/events")
    refute Dunda.Security.URL.safe_https_url?("https://127.0.0.1/events")
    refute Dunda.Security.URL.safe_https_url?("https://[::1]/events")
    refute Dunda.Security.URL.safe_https_url?("https://example.com:8443/events")
    refute Dunda.Security.URL.safe_https_url?("https://user:pass@example.com/events")
    refute Dunda.Security.URL.safe_https_url?("file:///etc/passwd")
  end

  test "host allow-list supports exact hosts and subdomains only" do
    Application.put_env(:dunda, :scraper_allowed_hosts, ["example.com"])

    assert Dunda.Security.URL.safe_https_url?("https://example.com/events")
    assert Dunda.Security.URL.safe_https_url?("https://www.example.com/events")
    refute Dunda.Security.URL.safe_https_url?("https://example.com.evil.test/events")
  end
end
