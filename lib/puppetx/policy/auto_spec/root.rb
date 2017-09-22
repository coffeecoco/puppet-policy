Puppetx::Policy::AutoSpec.newspec 'root' do |u|
  content = "  describe user('root') do\n"
  content += "    its(:minimum_days_between_password_change) { should eq 10 }\n"
  content += "  end\n"
end
