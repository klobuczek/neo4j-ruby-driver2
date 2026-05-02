# frozen_string_literal: true

RSpec.describe Neo4j::Driver::Bolt::Connection do
  let(:auth) { { scheme: 'none' } }

  # Build a connection without actually connecting to anything
  def build_connection(uri, options = {})
    described_class.new(uri, auth, options)
  end

  describe '#format_address (private)' do
    subject(:conn) { build_connection('bolt://localhost:7687') }

    it 'returns "host:port" for IPv4' do
      expect(conn.send(:format_address, '127.0.0.1', 7687)).to eq('127.0.0.1:7687')
    end

    it 'wraps bare IPv6 in brackets' do
      expect(conn.send(:format_address, '::1', 7687)).to eq('[::1]:7687')
    end

    it 'does not double-bracket already-bracketed IPv6' do
      expect(conn.send(:format_address, '[::1]', 7687)).to eq('[::1]:7687')
    end

    it 'wraps full IPv6 address in brackets' do
      expect(conn.send(:format_address, '2001:db8::1', 7687)).to eq('[2001:db8::1]:7687')
    end
  end

  describe '#strip_brackets (private)' do
    subject(:conn) { build_connection('bolt://localhost:7687') }

    it 'strips brackets from IPv6 host' do
      expect(conn.send(:strip_brackets, '[::1]')).to eq('::1')
    end

    it 'leaves IPv4 host unchanged' do
      expect(conn.send(:strip_brackets, '127.0.0.1')).to eq('127.0.0.1')
    end

    it 'leaves bare IPv6 host unchanged' do
      expect(conn.send(:strip_brackets, '::1')).to eq('::1')
    end

    it 'handles nil gracefully' do
      expect(conn.send(:strip_brackets, nil)).to be_nil
    end
  end

  describe '#split_addr (private)' do
    subject(:conn) { build_connection('bolt://localhost:7687') }

    it 'splits "host:port" for IPv4' do
      expect(conn.send(:split_addr, '127.0.0.1:7687', 7687)).to eq(['127.0.0.1', 7687])
    end

    it 'splits "[::1]:port" for IPv6 and keeps brackets on host' do
      expect(conn.send(:split_addr, '[::1]:7687', 7687)).to eq(['[::1]', 7687])
    end

    it 'uses default port when no port is given' do
      expect(conn.send(:split_addr, 'localhost', 7687)).to eq(['localhost', 7687])
    end
  end

  describe '#resolved_addresses (private)' do
    context 'with a plain IPv4 URI and no resolver' do
      subject(:conn) { build_connection('bolt://127.0.0.1:7687') }

      it 'returns [["127.0.0.1", 7687]]' do
        expect(conn.send(:resolved_addresses)).to eq([['127.0.0.1', 7687]])
      end
    end

    context 'with an IPv6 URI and no resolver' do
      subject(:conn) { build_connection('bolt://[::1]:7687') }

      # Ruby 3.4+: URI("bolt://[::1]:7687").host => "[::1]" (brackets preserved)
      it 'returns [["[::1]", 7687]]' do
        expect(conn.send(:resolved_addresses)).to eq([['[::1]', 7687]])
      end
    end

    context 'with a resolver that returns an IPv6 address' do
      subject(:conn) do
        build_connection('bolt://example.com:7687', resolver: ->(_addr) { '[::1]:7688' })
      end

      it 'returns the bracketed IPv6 host and resolved port' do
        expect(conn.send(:resolved_addresses)).to eq([['[::1]', 7688]])
      end
    end

    context 'with a resolver that returns multiple addresses' do
      subject(:conn) do
        build_connection('bolt://example.com:7687', resolver: ->(_addr) { ['127.0.0.1:7687', '[::1]:7687'] })
      end

      it 'returns all resolved addresses' do
        expect(conn.send(:resolved_addresses)).to eq([['127.0.0.1', 7687], ['[::1]', 7687]])
      end
    end

    context 'resolver receives correctly-formatted IPv6 address' do
      subject(:received_addr) do
        received = nil
        conn = build_connection('bolt://[::1]:7687', resolver: ->(addr) { received = addr; [] })
        conn.send(:resolved_addresses)
        received
      end

      it 'passes "[::1]:7687" to the resolver (bracketed, Java-contract form)' do
        expect(subject).to eq('[::1]:7687')
      end
    end
  end

  describe '@address after successful connection' do
    # We verify the address is stored in canonical "host:port" form — specifically
    # that IPv6 uses "[host]:port" so Summary#server.address re-parses correctly.
    it 'stores IPv4 address as "host:port"' do
      conn = build_connection('bolt://127.0.0.1:7687')
      # Simulate a successful open_socket call by stubbing the socket
      allow(TCPSocket).to receive(:new).and_return(double('socket',
        setsockopt: nil, closed?: false, close: nil, flush: nil))
      allow(conn).to receive(:perform_handshake)
      allow(conn).to receive(:perform_hello)
      conn.connect
      expect(conn.address).to eq('127.0.0.1:7687')
    end

    it 'stores IPv6 address as "[host]:port" (bracketed)' do
      conn = build_connection('bolt://[::1]:7687')
      # Ruby 3.4+: @uri.host returns "[::1]"; format_address preserves the brackets
      allow(TCPSocket).to receive(:new).and_return(double('socket',
        setsockopt: nil, closed?: false, close: nil, flush: nil))
      allow(conn).to receive(:perform_handshake)
      allow(conn).to receive(:perform_hello)
      conn.connect
      expect(conn.address).to eq('[::1]:7687')
    end
  end
end
