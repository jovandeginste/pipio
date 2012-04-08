require 'spec_helper'

describe Pidgin2Adium::XMLMessage, '#to_s' do
  let(:sender_screen_name) { 'jim_sender' }
  let(:time) { Time.now }
  let(:sender_alias) { 'jane_alias' }
  let(:body) { 'body' }

  it 'has the correct sender_screen_name' do
    create_xml_message.to_s.should include %(sender="#{sender_screen_name}")
  end

  it 'has the correct alias' do
    create_xml_message.to_s.should include %(alias="#{sender_alias}")
  end

  it 'has the correct time' do
    time = Time.now
    formatted_time = time.strftime('%Y-%m-%dT%H:%M:%S%Z')
    result = Pidgin2Adium::XMLMessage.new(sender_screen_name, time, sender_alias, body).to_s
    result.should include %(time="#{formatted_time}")
  end

  it 'has the correct body' do
    styled_body = %(<div><span style="font-family: Helvetica; font-size: 12pt;">#{body}</span></div>)
    create_xml_message.to_s.should include styled_body
  end

  context "normalization" do
    it 'balances the tags in the body' do
      unbalanced_body = '<div>unbalanced'
      balanced_message = Pidgin2Adium::XMLMessage.new(sender_screen_name, time, sender_alias, unbalanced_body)
      balanced_message.body.should == '<div>unbalanced</div>'
    end

    it 'removes *** from the beginning of the buddy alias' do
      alias_with_stars = '***Jim'
      alias_without_stars = 'Jim'
      xml_message = Pidgin2Adium::XMLMessage.new(sender_screen_name, time, alias_with_stars, body)
      xml_message.to_s.should include %(alias="#{alias_without_stars}")
    end

    it 'escapes & to &amp;' do
      ampersand = '&'
      xml_message = Pidgin2Adium::XMLMessage.new(sender_screen_name, time, sender_alias, ampersand)
      xml_message.body.should == '&amp;'
    end

    %w(lt gt amp quot apos).each do |entity|
      it "does not escape &#{entity};" do
        entity_body = "&#{entity};"
          xml_message = Pidgin2Adium::XMLMessage.new(sender_screen_name, time, sender_alias, entity_body)
        xml_message.body.should == entity_body
      end
    end
  end

  def create_xml_message
    Pidgin2Adium::XMLMessage.new(sender_screen_name, time, sender_alias, body)
  end
end
