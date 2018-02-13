# -*- coding: utf-8 -*-
#
# SSLの有効期限をチェックし、45,30,15,7,3,1日前に通知メールを送信します。
# 1日1回動かす前提です。

require 'yaml'
require 'pp'
require 'mail'
require 'erb'
require 'socket'
require 'openssl'
require 'active_support'
require 'active_support/core_ext'

#　通知する間隔
ALERT_BEFORE_LIMIT_DAY = [45,30,15,7,3,1]

# https://qiita.com/QUANON/items/47f862bc3abaf9f302ec より
def get_certificate(host)
  certificate = nil

  TCPSocket.open(host, 443) do |tcp_client|
    ssl_client = OpenSSL::SSL::SSLSocket.new(tcp_client)
    ssl_client.hostname = host
    ssl_client.connect
    certificate = ssl_client.peer_cert
    ssl_client.close
  end

  certificate
end
def time2str(time)
  d = time.strftime('%Y/%m/%d')
  w = %w(日 月 火 水 木 金 土)[time.wday]
  t = time.strftime('%H:%M:%S')

  "#{d} (#{w}) #{t}"
end

def main
  begin
    # YAMLをOpen
    chk_hosts = YAML.load_file("chk_hosts.yml")
    mail_from = chk_hosts['mail_from']
    chk_hosts = chk_hosts['chk_host_list']
  rescue Errno::ENOENT
    puts "ERROR:YAMLファイルが開けません"
    exit(1)
  rescue Psych::SyntaxError
    puts "ERROR:YAMLファイルのパースに失敗"
    exit(1)
  end

  # SSLチェック
  chk_hosts.each do |chk|
    hostname = chk["uri"]
    begin
      certificate = get_certificate(hostname)
    rescue SocketError, OpenURI::HTTPError 
      puts "サーバが見つかりません。無視します。：#{hostname}"
      next
    end
    not_after = certificate.not_after.in_time_zone('Japan')

    diff = ((not_after - Time.now) / 1.days)
    pp hostname
    puts("有効期限: #{time2str(not_after)} (残り #{diff.to_i} 日)")
    # メール送信
    if ALERT_BEFORE_LIMIT_DAY.include?(diff.to_i)
      # メールテンプレート展開
      output = ERB.new(open('mail.erb').read, nil, '-').result(binding)
      chk["mail"].each do |mail|
        mail = Mail.new do
          from mail_from
          to mail
          subject "SSL証明書有効期限通知(#{hostname})#{diff.to_i}日前"
          body output
        end
        mail.charset = 'utf-8'
        mail.delivery_method :sendmail
        mail.deliver
      end
    end
  end
  exit(0)
end

main