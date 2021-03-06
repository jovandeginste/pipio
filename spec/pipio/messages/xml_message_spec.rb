describe Pipio::XMLMessage, '#to_s' do
  it 'has the correct sender_screen_name' do
    expect(create_xml_message(sender_screen_name: 'jim').to_s).to include %(sender="jim")
  end

  it 'has the correct alias' do
    expect(create_xml_message(sender_alias: 'Jim Alias').to_s).to include %(alias="Jim Alias")
  end

  it 'has the correct time' do
    time = Time.now
    formatted_time = time.xmlschema.sub(/:00$/, "00")
    expect(create_xml_message(time: time).to_s).to include %(time="#{formatted_time}")
  end

  it 'has the correct body' do
    unstyled_body = 'unstyled'
    styled_body = %(<div><span style="font-family: Helvetica; font-size: 12pt;">#{unstyled_body}</span></div>)
    expect(create_xml_message(body: unstyled_body).to_s).to include styled_body
  end

  context "normalization" do
    it 'balances the tags in the body' do
      unbalanced_body = '<div>unbalanced'
      expect(create_xml_message(body: unbalanced_body).body).to eq('<div>unbalanced</div>')
    end

    it 'removes *** from the beginning of the sender alias' do
      alias_with_stars = '***Jim'
      alias_without_stars = 'Jim'
      expect(create_xml_message(sender_alias: alias_with_stars).to_s).to include %(alias="#{alias_without_stars}")
    end

    it 'escapes & to &amp;' do
      expect(create_xml_message(body: '&').body).to eq('&amp;')
    end

    %w(lt gt amp quot apos).each do |entity|
      it "does not escape &#{entity};" do
        entity_body = "&#{entity};"
        expect(create_xml_message(body: entity_body).body).to eq(entity_body)
      end
    end
  end

  def create_xml_message(opts = {})
    opts[:sender_screen_name] ||= 'jim_sender'
    opts[:time] ||= Time.now
    opts[:sender_alias] ||= 'jane_alias'
    opts[:body] ||= 'body'
    opts[:event_type] ||= 'libPurpleEvent'

    Pipio::XMLMessage.new(opts[:sender_screen_name], opts[:time], opts[:sender_alias], opts[:body])
  end
end
