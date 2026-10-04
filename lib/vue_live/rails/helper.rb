# frozen_string_literal: true

module VueLive
  module Rails
    # ActionView flavour of VueLive::Helpers: html_safe output, automatic CSP nonces and
    # cooperation with importmap-rails (browsers honour only one import map per page).
    module Helper
      include VueLive::Helpers

      def vue_live_import_map_tag(imports: {}, nonce: nil)
        super(imports: imports, nonce: nonce || vue_live_csp_nonce).html_safe
      end

      def vue_live_mount_tag(component, selector = '#app', nonce: nil, **options)
        super(component, selector, nonce: nonce || vue_live_csp_nonce, **options).html_safe
      end

      def vue_live_module_tag(javascript, nonce: nil)
        super(javascript, nonce: nonce || vue_live_csp_nonce).html_safe
      end

      def vue_live_tags(component, selector = '#app', **options)
        super.html_safe
      end

      private

      def vue_live_csp_nonce
        respond_to?(:content_security_policy_nonce, true) ? content_security_policy_nonce : nil
      end

      # importmap-rails owns the page's import map; the Railtie pins `vue` into it instead.
      # Set config.vue_live.importmap_pin = false to keep the two separate.
      def vue_live_external_importmap?
        defined?(::Importmap::Map) && VueLive.config.importmap_pin ? true : false
      end
    end
  end
end
