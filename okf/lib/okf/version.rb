# frozen_string_literal: true

module OKF
  VERSION = "1.13.0"

  # The OKF spec version this gem targets — one declaration behind the validate
  # header and its help row, so the version a bundle is judged against cannot
  # be stated two ways. The gem still *reads* v0.1 (§13.1); this is what it
  # validates for. Known readable versions: Concept::KNOWN_SPEC_VERSIONS.
  SPEC_VERSION = "0.2"
end
