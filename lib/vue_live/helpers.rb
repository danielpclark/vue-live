# frozen_string_literal: true

require 'json'

module VueLive
  # Framework-agnostic view helpers.  They return plain Strings; the Rails module wraps them in
  # html_safe and adds CSP nonces.  Include into any view context:
  #
  #   helpers VueLive::Helpers          # Sinatra
  #   include VueLive::Helpers          # ERB / Tilt / anything with a binding
  module Helpers
    # URL for a component (or any file under the component root), with a content digest for
    # cache busting:  vue_live_path('App.vue')  #=> "/vue/App.vue.js?v=1a2b3c4d5e6f7a8b"
    def vue_live_path(component)
      config = vue_live_config
      rel = component.to_s.sub(%r{\A/+}, '')
      if config.use_manifest?
        manifest = VueLive::Precompiler.manifest(config)
        return manifest[rel] || manifest[rel.sub(/\.vue\.js\z/, '.vue')] || "#{config.normalized_prefix}/#{rel}"
      end
      url = "#{config.normalized_prefix}/#{rel.end_with?('.vue') ? "#{rel}.js" : rel}"
      digest = rel.end_with?('.vue') ? VueLive.store.digest(rel) : nil
      digest ? "#{url}?v=#{digest}" : url
    end

    # The import map every page needs once, before any module script:
    #
    #   <script type="importmap">{"imports":{"vue":"https://cdn.jsdelivr.net/npm/vue@3/dist/vue.esm-browser.prod.js"}}</script>
    #
    # Extra entries come from config.import_map and the +imports+ argument.  Returns an empty
    # string when importmap-rails is managing the page's import map (the Railtie pins `vue` there).
    def vue_live_import_map_tag(imports: {}, nonce: nil)
      return '' if vue_live_external_importmap?

      map = { 'imports' => vue_live_import_map(imports) }
      %(<script type="importmap"#{vue_live_nonce_attr(nonce)}>#{JSON.generate(map).gsub('</', '<\/')}</script>)
    end

    def vue_live_import_map(extra = {})
      config = vue_live_config
      { 'vue' => config.resolved_vue_url }.merge(stringify_keys(config.import_map)).merge(stringify_keys(extra))
    end

    # <script type="module"> that imports a component and mounts it on +selector+:
    #
    #   vue_live_mount_tag 'App.vue', '#app', props: { user: current_user.name }
    #
    # Pass +create: false+ to get only the import and an exported `app` you can configure
    # yourself, or use vue_live_module_tag for arbitrary code.
    def vue_live_mount_tag(component, selector = '#app', props: {}, nonce: nil, element: false, plugins: [])
      config = vue_live_config
      url = vue_live_path(component)
      js = +''
      if config.vue_version.to_s.start_with?('2')
        js << "import Vue from 'vue'\nimport App from #{js_str(url)}\n"
        js << "new Vue({ render: h => h(App, { props: #{JSON.generate(props)} }) }).$mount(#{js_str(selector)})\n"
      else
        js << "import { createApp } from 'vue'\nimport App from #{js_str(url)}\n"
        js << "const app = createApp(App, #{JSON.generate(props)})\n"
        Array(plugins).each { |plugin| js << "app.use(#{plugin})\n" }
        js << "app.mount(#{js_str(selector)})\n"
      end
      tag = vue_live_module_tag(js, nonce: nonce)
      tag = "#{tag}\n#{vue_live_reload_tag(nonce: nonce)}" if config.live_reload?
      element ? "#{vue_live_mount_element(selector)}\n#{tag}" : tag
    end

    # Development live reload client (reloads the page when a component changes).  Included by
    # vue_live_mount_tag whenever config.live_reload? is on; renders nothing otherwise.
    def vue_live_reload_tag(nonce: nil)
      config = vue_live_config
      return '' unless config.live_reload?

      prefix = config.normalized_prefix
      %(<script src="#{prefix}/-/reload.js" data-events="#{prefix}/-/events" defer#{vue_live_nonce_attr(nonce)}></script>)
    end

    def vue_live_module_tag(javascript, nonce: nil)
      %(<script type="module"#{vue_live_nonce_attr(nonce)}>\n#{javascript.to_s.gsub('</script', '<\/script')}</script>)
    end

    # Everything a simple page needs: import map + mount script (+ the mount element).
    def vue_live_tags(component, selector = '#app', **options)
      [vue_live_import_map_tag(nonce: options[:nonce]), vue_live_mount_tag(component, selector, **options)].join("\n")
    end

    private

    def vue_live_config
      VueLive.config
    end

    def vue_live_mount_element(selector)
      if selector.start_with?('#')
        %(<div id="#{selector[1..]}"></div>)
      else
        %(<div class="#{selector.sub(/\A\./, '')}"></div>)
      end
    end

    # Overridden by the Rails helper to detect importmap-rails.
    def vue_live_external_importmap?
      false
    end

    def vue_live_nonce_attr(nonce)
      nonce ? %( nonce="#{nonce}") : ''
    end

    def js_str(str)
      JSON.generate(str.to_s).gsub('</', '<\/')
    end

    def stringify_keys(hash)
      (hash || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end
  end
end
