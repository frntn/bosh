require 'spec_helper'

describe Bosh::Clouds::ExternalCpi do
  let(:director_uuid) { 'fake-director-uuid' }
  subject(:external_cpi) { described_class.new('/path/to/fake-cpi/bin/cpi', director_uuid) }
  before { allow(File).to receive(:executable?).with('/path/to/fake-cpi/bin/cpi').and_return(true) }

  let(:cpi_response) do
    JSON.dump(
      result: nil,
      error: nil,
      log: ''
    )
  end

  let(:env) { {'TMPDIR' => '/some/tmp'} }
  before { stub_const('ENV', env) }

  let(:config) { double(:config, logger: double(:logger, debug: nil)) }
  before { stub_const('Bosh::Clouds::Config', config)}

  before { allow(Open3).to receive(:capture3).and_return([cpi_response, stderr, exit_status]) }
  let(:stderr) { double('fake-stderr-data') }
  let(:exit_status) { instance_double('Process::Status', exitstatus: 0) }

  def self.it_calls_cpi_method(method, cpi_method, *arguments)
    subject(:call_cpi_method) { external_cpi.public_send(method, *arguments) }

    it 'calls cpi binary with correct arguments' do
      expected_env = {'PATH' => '/usr/sbin:/usr/bin:/sbin:/bin', 'TMPDIR' => '/some/tmp'}
      expected_cmd = '/path/to/fake-cpi/bin/cpi'
      expected_stdin = %Q{{"method":"#{cpi_method}","arguments":#{arguments.to_json},"context":{"director_uuid":"#{director_uuid}"}}}

      expect(Open3).to receive(:capture3).with(expected_env, expected_cmd, stdin_data: expected_stdin).and_return([cpi_response, stderr, exit_status])
      call_cpi_method
    end

    describe 'result' do
      let(:result) { 'fake-result' }
      let(:cpi_response) do
        JSON.dump({
          result: result,
          error: nil,
          log: 'fake-log'
        })
      end

      it 'returns result' do
        expect(call_cpi_method).to eq(result)
      end
    end

    context 'when response is not a valid JSON' do
      let(:cpi_response) { 'invalid-json' }

      it 'raises an error' do
        expect {
          call_cpi_method
        }.to raise_error(
          Bosh::Clouds::ExternalCpi::InvalidResponse
        )
      end
    end

    context 'when response is in incorrect format' do
      let(:cpi_response) { JSON.dump({some_key: 'some_value'}) }

      it 'raises an error' do
        expect {
          call_cpi_method
        }.to raise_error(
          Bosh::Clouds::ExternalCpi::InvalidResponse
        )
      end
    end

    context 'when cpi command is not executable' do
      before { allow(File).to receive(:executable?).with('/path/to/fake-cpi/bin/cpi').and_return(false) }

      it 'raises MessageHandlerError' do
        expect {
          call_cpi_method
        }.to raise_error(
          Bosh::Clouds::ExternalCpi::NonExecutable,
          "Failed to run cpi: `/path/to/fake-cpi/bin/cpi' is not executable",
        )
      end
    end

    describe 'error response' do
      def self.it_raises_an_error_with_ok_to_retry(error_class, message)
        let(:cpi_response) do
          JSON.dump(
            result: nil,
            error: {
              type: error_class.name,
              message: message,
              ok_to_retry: true
            },
            log: 'fake-log'
          )
        end

        it 'raises an error constructed from error response' do
          expect {
            call_cpi_method
          }.to raise_error do |error|
            expect(error.class).to eq(error_class)
            expect(error.message).to eq(message)
            expect(error.ok_to_retry).to eq(true)
          end
        end
      end

      def self.it_raises_an_error(error_class, message)
        let(:cpi_response) do
          JSON.dump(
            result: nil,
            error: {
              type: error_class.name,
              message: message,
              ok_to_retry: true
            },
            log: 'fake-log'
          )
        end

        it 'raises an error constructed from error response' do
          expect {
            call_cpi_method
          }.to raise_error do |error|
            expect(error.class).to eq(error_class)
            expect(error.message).to eq(message)
          end
        end
      end

      context 'when cpi returns a NoDiskSpace error' do
        it_raises_an_error_with_ok_to_retry(Bosh::Clouds::NoDiskSpace, 'Not enough disk space')
      end

      context 'when cpi returns a DiskNotAttached error' do
        it_raises_an_error_with_ok_to_retry(Bosh::Clouds::DiskNotAttached, 'Not enough disk space')
      end

      context 'when cpi returns a DiskNotFound error' do
        it_raises_an_error_with_ok_to_retry(Bosh::Clouds::DiskNotFound, 'Not enough disk space')
      end

      context 'when cpi returns a VMCreationFailed error' do
        it_raises_an_error_with_ok_to_retry(Bosh::Clouds::VMCreationFailed, 'Not enough disk space')
      end

      context 'when cpi returns CloudError error' do
        it_raises_an_error(Bosh::Clouds::CloudError, 'Something went wrong')
      end

      context 'when cpi returns CpiError error' do
        it_raises_an_error(Bosh::Clouds::CpiError, 'Something went wrong')
      end

      context 'when cpi raises unrecognizable error' do
        let(:cpi_response) do
          JSON.dump(
            result: nil,
            error: {
              type: 'FakeUnrecognizableError',
              message: 'Something went wrong',
              ok_to_retry: true
            },
            log: 'fake-log'
          )
        end

        it 'raises an error constructed from error response' do
          expect {
            call_cpi_method
          }.to raise_error { |error|
            expect(error.class).to eq(Bosh::Clouds::ExternalCpi::UnknownError)
            expect(error.message).to eq('Received unknown error from cpi: FakeUnrecognizableError with message Something went wrong')
          }
        end
      end
    end

    context 'when exit status is non zero' do
      let(:exit_status) { instance_double('Process::Status', exitstatus: 123) }

      it 'ignores the exit status and returns result because the CPI script currently catches CPI error and returns response' do
        expect {
          call_cpi_method
        }.to_not raise_error
      end
    end
  end

  describe '#current_vm_id' do
    it_calls_cpi_method(:current_vm_id, :current_vm_id)
  end

  describe '#create_stemcell' do
    it_calls_cpi_method(:create_stemcell, :create_stemcell, 'fake-stemcell-image-path', {'cloud' => 'props'})
  end

  describe '#delete_stemcell' do
    it_calls_cpi_method(:delete_stemcell, :delete_stemcell, 'fake-stemcell-cid')
  end

  describe '#create_vm' do
    it_calls_cpi_method(:create_vm,
      :create_vm,
      'fake-agent-id',
      'fake-stemcell-cid',
      {'cloud' => 'props'},
      {'net' => 'props'},
      ['fake-disk-cid'],
      {'env' => 'props'}
    )
  end

  describe '#delete_vm' do
    it_calls_cpi_method(:delete_vm, :delete_vm, 'fake-vm-cid')
  end

  describe '#has_vm?' do
    it_calls_cpi_method(:has_vm?, :has_vm, 'fake-vm-cid')
  end

  describe '#reboot_vm' do
    it_calls_cpi_method(:reboot_vm, :reboot_vm, 'fake-vm-cid')
  end

  describe '#set_vm_metadata' do
    it_calls_cpi_method(:set_vm_metadata, :set_vm_metadata, 'fake-vm-cid', {'metadata' => 'hash'})
  end

  describe '#configure_networks' do
    it_calls_cpi_method(:configure_networks, :configure_networks, 'fake-vm-cid', {'net' => 'props'})
  end

  describe '#create_disk' do
    it_calls_cpi_method(:create_disk, :create_disk, 100_000, 'fake-vm-cid')
  end

  describe '#delete_disk' do
    it_calls_cpi_method(:delete_disk, :delete_disk, 'fake-disk-cid')
  end

  describe '#attach_disk' do
    it_calls_cpi_method(:attach_disk, :attach_disk, 'fake-vm-cid', 'fake-disk-cid')
  end

  describe '#detach_disk' do
    it_calls_cpi_method(:detach_disk, :detach_disk, 'fake-vm-cid', 'fake-disk-cid')
  end

  describe '#snapshot_disk' do
    it_calls_cpi_method(:snapshot_disk, :snapshot_disk, 'fake-disk-cid')
  end

  describe '#delete_snapshot' do
    it_calls_cpi_method(:delete_snapshot, :delete_snapshot, 'fake-snapshot-cid')
  end

  describe '#get_disks' do
    it_calls_cpi_method(:get_disks, :get_disks, 'fake-vm-cid')
  end

  describe '#ping' do
    it_calls_cpi_method(:ping, :ping)
  end
end
