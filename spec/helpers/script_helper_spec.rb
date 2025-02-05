require 'rails_helper'

RSpec.describe ScriptHelper do
  include ScriptHelper

  describe '#javascript_include_tag_without_preload' do
    it 'avoids modifying headers' do
      javascript_include_tag_without_preload 'application'

      expect(response.header['Link']).to be_nil
    end
  end

  describe '#javascript_packs_tag_once' do
    it 'returns nil' do
      output = javascript_packs_tag_once('application')

      expect(output).to be_nil
    end
  end

  describe '#render_javascript_pack_once_tags' do
    context 'no scripts enqueued' do
      it 'is nil' do
        expect(render_javascript_pack_once_tags).to be_nil
      end
    end

    context 'scripts enqueued' do
      before do
        javascript_packs_tag_once('clipboard', 'clipboard')
        javascript_packs_tag_once('document-capture')
        javascript_packs_tag_once('application', prepend: true)
      end

      it 'prints all unique packs in order, locale scripts first' do
        output = render_javascript_pack_once_tags
        public_output_path = current_webpacker_instance.config.public_output_path
        public_path = current_webpacker_instance.config.public_path
        output_path = public_output_path.relative_path_from(public_path)

        selectors = [
          "script[src^='/#{output_path}/js/application-'][src$='.chunk.en.js']",
          "script[src^='/#{output_path}/js/document-capture-'][src$='.chunk.en.js']",
          "script[src^='/#{output_path}/js/runtime~application-']",
          "script[src^='/#{output_path}/js/application-'][src$='.chunk.js']",
          "script[src^='/#{output_path}/js/clipboard-'][src$='.chunk.js']",
          "script[src^='/#{output_path}/js/document-capture-'][src$='.chunk.js']",
        ]

        selectors.each_with_index do |selector, i|
          next_selector = selectors[i + 1]
          test_selector = selector
          test_selector += " ~ #{next_selector}" if next_selector
          expect(output).to have_css(test_selector, count: 1, visible: false)
        end
      end
    end
  end
end
