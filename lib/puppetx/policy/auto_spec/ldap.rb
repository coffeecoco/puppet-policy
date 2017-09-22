Puppetx::Policy::AutoSpec.newspec 'Apache::Vhost' do |v|
  should = (p[:ensure] == 'absent') ? 'should_not' : 'should'
  "  describe port('#{v[:port]}') do\n     it { #{should} be_listening }\n  end\n" if v[:port]
end
