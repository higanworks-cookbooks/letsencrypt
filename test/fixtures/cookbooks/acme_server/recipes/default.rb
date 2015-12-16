#
# Author:: Thijs Houtenbos <thoutenbos@schubergphilis.com>
# Cookbook:: acme_server
# Recipe:: default
#
# Copyright 2015 Schuberg Philis
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package 'git'
package 'screen'
package 'mariadb-server'
package 'libtool-ltdl-devel'

service 'mariadb' do
  action :start
end

include_recipe 'build-essential'
include_recipe 'rabbitmq'
include_recipe 'golang'

chef_gem 'rest-client' do
  action :install
  compile_time false
end

boulderdir = "#{node['go']['gopath']}/src/github.com/letsencrypt/boulder"

directory ::File.dirname boulderdir do
  recursive true
end

git boulderdir do
  repository 'https://github.com/letsencrypt/boulder'
  revision '8e6f13f189d7e7feb0f5407a9a9c63f3b644f730'
  action :checkout
end

ruby_block 'boulder_config' do
  block do
    config = ::JSON.parse ::File.read "#{boulderdir}/test/boulder-config.json"
    config['va']['portConfig']['httpPort'] = 80
    config['va']['portConfig']['httpsPort'] = 443
    config['va']['portConfig']['tlsPort'] = 443
    ::File.write("#{boulderdir}/test/boulder-config.json", ::JSON.pretty_generate(config))
  end
end

bash 'setup' do
  cwd boulderdir
  code 'source /etc/profile.d/golang.sh && ./test/setup.sh && touch setup.done'
  not_if { ::File.exist? "#{boulderdir}/setup.done" }
end

bash 'run_boulder' do
  cwd boulderdir
  code 'source /etc/profile.d/golang.sh && /bin/screen -dmS boulder ./start.py'
  not_if '/bin/screen -list boulder | /bin/grep 1\ Socket\ in'
end

ruby_block 'wait_for_bootstrap' do
  block do
    require 'rest-client'
    times = 0
    loop do
      times += 1
      begin
        client = RestClient.get 'http://127.0.0.1:4000/directory'
      rescue
        sleep 10
      end
      Chef::Application.fatal!('Failed to run boulder server') if times > 180
      break if client && client.code == 200
    end
  end
end
