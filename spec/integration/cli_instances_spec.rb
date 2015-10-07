require 'spec_helper'

describe 'cli: deployment process', type: :integration do
  include Bosh::Spec::CreateReleaseOutputParsers
  with_reset_sandbox_before_each

  it 'check output for BOSH INSTANCES', dns: true do
    target_and_login

    cloud_config_hash = Bosh::Spec::Deployments.simple_cloud_config
    cloud_config_hash['availability_zones'] = [
      {'name' => 'zone-1', 'cloud_properties' => {}},
      {'name' => 'zone-2', 'cloud_properties' => {}},
      {'name' => 'zone-3', 'cloud_properties' => {}},
    ]
    cloud_config_hash['networks'].first['subnets'] = [
      {
        'range' => '192.168.1.0/24',
        'gateway' => '192.168.1.1',
        'dns' => ['192.168.1.1', '192.168.1.2'],
        'static' => ['192.168.1.10'],
        'reserved' => [],
        'cloud_properties' => {},
        'availability_zone' => 'zone-1',
      },
      {
        'range' => '192.168.2.0/24',
        'gateway' => '192.168.2.1',
        'dns' => ['192.168.2.1', '192.168.2.2'],
        'static' => ['192.168.2.10'],
        'reserved' => [],
        'cloud_properties' => {},
        'availability_zone' => 'zone-2',
      },
      {
        'range' => '192.168.3.0/24',
        'gateway' => '192.168.3.1',
        'dns' => ['192.168.3.1', '192.168.3.2'],
        'static' => ['192.168.3.10'],
        'reserved' => [],
        'cloud_properties' => {},
        'availability_zone' => 'zone-3',
      }
    ]

    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['jobs'].first['availability_zones'] = ['zone-1', 'zone-2', 'zone-3']
    deploy_from_scratch(manifest_hash: manifest_hash, cloud_config_hash: cloud_config_hash)

    output = bosh_runner.run('instances --details')

    output = scrub_random_ids(output)
    expect(output).to include('VM CID')
    expect(output).to include('Disk CID')
    expect(output).to include('Agent ID')
    expect(output).to include('Resurrection')

    output = bosh_runner.run('instances --dns')
    expect(scrub_random_ids(output)).to include(<<INSTANCES)
+--------------------------------------------------+---------+--------+---------------+-------------+-----------------------------------------------------------+
| Instance                                         | State   | AZ     | Resource Pool | IPs         | DNS A records                                             |
+--------------------------------------------------+---------+--------+---------------+-------------+-----------------------------------------------------------+
| foobar/0 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)* | running | zone-1 | a             | 192.168.1.2 | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.foobar.a.simple.bosh |
|                                                  |         |        |               |             | 0.foobar.a.simple.bosh                                    |
| foobar/1 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)  | running | zone-2 | a             | 192.168.2.2 | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.foobar.a.simple.bosh |
|                                                  |         |        |               |             | 1.foobar.a.simple.bosh                                    |
| foobar/2 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)  | running | zone-3 | a             | 192.168.3.2 | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.foobar.a.simple.bosh |
|                                                  |         |        |               |             | 2.foobar.a.simple.bosh                                    |
+--------------------------------------------------+---------+--------+---------------+-------------+-----------------------------------------------------------+

(*) Bootstrap node
INSTANCES

    output = bosh_runner.run('instances')
    expect(scrub_random_ids(output)).to include(<<INSTANCES)
+--------------------------------------------------+---------+--------+---------------+-------------+
| Instance                                         | State   | AZ     | Resource Pool | IPs         |
+--------------------------------------------------+---------+--------+---------------+-------------+
| foobar/0 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)* | running | zone-1 | a             | 192.168.1.2 |
| foobar/1 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)  | running | zone-2 | a             | 192.168.2.2 |
| foobar/2 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)  | running | zone-3 | a             | 192.168.3.2 |
+--------------------------------------------------+---------+--------+---------------+-------------+

(*) Bootstrap node
INSTANCES

  end

  it 'should return instances --vitals' do
    deploy_from_scratch

    all_vitals = director.instances_vitals
    vitals = all_vitals[0]

    expect(vitals[:cpu_user]).to match /\d+\.?\d*[%]/
    expect(vitals[:cpu_sys]).to match /\d+\.?\d*[%]/
    expect(vitals[:cpu_wait]).to match /\d+\.?\d*[%]/

    expect(vitals[:memory_usage]).to match /\d+\.?\d*[%] \(\d+\.?\d*\w\)/
    expect(vitals[:swap_usage]).to match /\d+\.?\d*[%] \(\d+\.?\d*\w\)/

    expect(vitals[:system_disk_usage]).to match /\d+\.?\d*[%]/
    expect(vitals[:ephemeral_disk_usage]).to match /\d+\.?\d*[%]/

    # persistent disk was not deployed
    expect(vitals[:persistent_disk_usage]).to match /n\/a/
  end

  it 'should return instances --ps' do
    deploy_from_scratch
    instances_ps = director.instances_ps

    expect(instances_ps[0][:instance]).to match /foobar\/0/
    expect(instances_ps[1][:instance]).to match /process-1/
    expect(instances_ps[1][:state]).to match /running/
    expect(instances_ps[2][:instance]).to match /process-2/
    expect(instances_ps[2][:state]).to match /running/
  end
end