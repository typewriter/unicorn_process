# -*- coding: utf-8 -*-

#
#= unicorn_railsの情報を収集するクラス
#
#Authors:: typewriter
#Version:: 0.52
#License:: MIT
#
#== 動作条件
#
#* /proc ファイルシステムが利用できる
#* unicorn_rails によってRailsアプリケーションが動作している
#* netstatが利用できる
#
#== Sample
#
# require './unicorn_process.rb'
# processes = UnicornProcess.processes
# processes.each { |process|
#   puts "PID: #{process.pid}, ポート: #{process.port}, アプリディレクトリ: #{process.working_directory}"
# }
class UnicornProcess
  # 動作状況を調べるためのシステムコールの実行結果をキャッシュします。
  # (複数の動作状況を調べたり、繰り返しメソッドを呼び出したりする場合にパフォーマンスが向上します)
  # キャッシュをクリアするには、 clear クラスメソッドを呼び出します。
  CACHED_RESULT = false

  # 指定したプロセスIDの情報を収集するオブジェクトを生成します。
  def initialize(pid)
    @pid = pid
  end

  # キャッシュをクリアします。
  def self.clear
    @@netstat = `netstat -anp`
    @@psaxl = `ps axl`
    @@rubies = {}
  end

  # 動作しているunicorn_railsを検索し、UnicornProcessの配列を返します。
  def self.processes
    unicorn_processes = []

    ps_result = `ps aux -ww`
    ps_result.each_line { |e|
      if e =~ /^.+?\s+(\d+)\s+.+\s+unicorn_rails master/
        process_id = $1.to_i
        unicorn_processes << UnicornProcess.new(process_id) if e !~ /\(old\)/
      end
    }

    unicorn_processes
  end

  # このオブジェクトが情報を収集するunicorn_railsのプロセスIDを示します。
  def pid
    @pid
  end

  # unicorn_railsが接続を受け付けるポートを示します。
  # 戻り値は配列です。配列の各要素は :port, :type キーを持ったハッシュです。:typeはソケットの種類("unix": Unixドメインソケット, "tcp": TCPソケット)、:portはポート番号(I-Node番号)を表します。
  # 権限等の問題で取得できない場合があります。
  def port
    # まあ、コンフィグを解釈するとかめんどいわけで。
    ports = []

    netstat_result = (CACHED_RESULT ? (defined?(@@netstat) ? @@netstat : @@netstat = `netstat -anp`) : `netstat -anp`)
    childs = child_pids
    netstat_result.each_line { |e|
      if e =~ /\s+#{@pid}\// || (!childs.empty? && e =~ /\s+(?:#{childs.join('|')})\//)
        # unix domain
        if e =~ /LISTENING\s+(\d+)\s+/
          ports << { :port => $1.to_i, :type => "unix" }
        elsif e =~ /[^:]\:(\d+)\s+.+?\s+LISTEN/
          ports << { :port => $1.to_i, :type => "tcp" }
        end
      end
    }
    ports
  end

  # unicorn_rails 起動時に --path で与えたパスを示します。
  # RAILS_RELATIVE_URL_ROOTに設定されるものです。
  # 設定が読み取れない場合は / (デフォルト) です。
  def path
    cmdline = File.read("#{proc_path}/cmdline")
    if cmdline =~ /\-\-path(?:\s+|=)([^ ]+)/
      $1.unpack("Z*").first
    else
      "/"
    end
  end

  # 現在の worker の数を示します。
  def worker
    workers = 0

    ps_result = (CACHED_RESULT ? (defined?(@@psaxl) ? @@psaxl : @@psaxl = `ps axl -ww`) : `ps axl -ww`)
    ps_result.each_line { |e|
      if e =~ /^\d+\s+\d+\s+\d+\s+#{@pid}\s+.+\s+unicorn_rails worker/
        workers += 1
      end
    }

    workers
  end

  # 動作している ruby インタプリタのバージョンを示します。
  # (rvmなどを利用している場合向けのメソッドです)
  # 権限等の問題で取得できない場合は nil です。
  def ruby_version
    begin
      exe = File.readlink("#{proc_path}/exe")

      if CACHED_RESULT
        @@rubies = {} if !defined?(@@rubies)
        (@@rubies[exe] ? @@rubies[exe] : @@rubies[exe] = `#{exe} -v`.chomp)
      else
        `#{exe} -v`.chomp
      end
    rescue
      nil
    end
  end

  # 作業ディレクトリを示します。
  # 通常、アプリケーションのディレクトリを指します。
  # 権限等の問題で取得できない場合は nil です。
  def working_directory
    begin
      File.readlink("#{proc_path}/cwd")
    rescue
      nil
    end
  end

  # unicorn_rails 起動時に -c または --config-file で与えた設定ファイルへのパスを示します。
  # 指定されていない場合は nil です。
  # また、作業ディレクトリが取得できない場合は相対パスを示します。
  def config_path
    cmdline = File.read("#{proc_path}/cmdline")
    if cmdline =~ /(?:\-c|\-\-config\-file)(?:\s+|=)([^ ]+)/
      if working_directory
        File.expand_path($1.unpack("Z*").first, working_directory)
      else
        $1.unpack("Z*").first
      end
    else
      nil
    end
  end

private
  def proc_path
    "/proc/#{@pid}"
  end

  def child_pids
    pids = []
    ps_result = (CACHED_RESULT ? (defined?(@@psaxl) ? @@psaxl : @@psaxl = `ps axl -ww`) : `ps axl -ww`)
    ps_result.each_line { |e|
      if e =~ /^\d+\s+\d+\s+(\d+)\s+#{@pid}\s+.+\s+unicorn_rails worker/
        pids << $1.to_i
      end
    }
    pids
  end
end

