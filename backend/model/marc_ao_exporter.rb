require 'date'
require 'net/sftp'

class MarcAOExporter

  # allowing for transactions in flight
  WINDOW_SECONDS = 5

  def self.run
    start = Time.now
    status = :ok

    Log.info("marcao: MARC AO Exporter running")

    res_ids = UserDefined.filter(AppConfig[:marcao_flag_field].intern => 1).filter(Sequel.~(:resource_id => nil)).select(:resource_id).all.map{|r| r[:resource_id]}

    ao_ds = ArchivalObject.any_repo.filter(:root_record_id => res_ids)

    if report = last_report
      since = DateTime.parse(report['export_started_at']).to_time - WINDOW_SECONDS
      ao_ds = ao_ds.where{system_mtime > since}
    end

    ao_count = ao_ds.count
    ao_jsons = to_enum(:each_resolved_ao, ao_ds)

    File.open(export_file_path + ".tmp", 'w:UTF-8') do |fh|
      fh.write(MarcAOMapper.collection_to_marc(ao_jsons))
    end

    File.rename(export_file_path + ".tmp", export_file_path)

    if AppConfig[:marcao_sftp_enabled]
      max_retries = 10

      max_retries.times do |retry_count|
        if retry_count > 0
          Log.info("marcao: Retrying SFTP upload (retry number #{retry_count})")
        end

        Net::SFTP.start(AppConfig[:marcao_sftp_host], AppConfig[:marcao_sftp_user], { password: AppConfig[:marcao_sftp_password] }) do |sftp|
          sftp.upload!(export_file_path, File.join(AppConfig[:marcao_sftp_path], File.basename(export_file_path)))
        end
        break
      rescue
        Log.warn("marcao: Upload to SFTP failed: #{$!}")
        if (retry_count + 1) < max_retries
          remaining_retries = max_retries - retry_count - 1
          Log.warn("marcao: Will retry #{remaining_retries} more time#{((remaining_retries == 1) ? '' : 's')}")
          sleep 30
        else
          status = :sftp_fail
          Log.error("marcao: SFTP upload has failed #{max_retries} times.  Giving up!")
        end
      end
    else
      status = :no_sftp
    end

    report = {
      :status => status,
      :export_started_at => start,
      :export_completed_at => Time.now,
      :export_file => export_file_path,
      :resource_ids_selected => res_ids,
      :archival_objects_exported => ao_count,
    }

    File.open(report_file_path + ".tmp", 'w:UTF-8') do |fh|
      fh.write(report.to_json)
    end

    File.rename(report_file_path + ".tmp", report_file_path)

    report
  end

  def self.each_resolved_ao(ao_ds, &block)
    grouped_ids = ao_ds
      .select(:repo_id, :id)
      .all
      .group_by(&:repo_id)
      .map {|repo_id, rows| [repo_id, rows.map {|row| row[:id]}]}
      .to_h

    grouped_ids.each do |repo_id, ao_ids|
      ao_ids.each_slice(100) do |batch|
        RequestContext.open(:repo_id => repo_id) do
          URIResolver.resolve_references(ArchivalObject.sequel_to_jsonmodel(ArchivalObject.filter(:id => batch).all),
                                         MarcAOMapper.resolves)
            .each do |resolved_json|
            block.call(resolved_json)
          end
        end
      end
    end
  end

  def self.last_report
    if File.exist?(report_file_path)
      ASUtils.json_parse(File.read(report_file_path))
    end
  end

  def self.export_file_path
    File.join(basedir, 'marcao_export.xml')
  end

  def self.report_file_path
    File.join(basedir, 'report.json')
  end

  def self.basedir
    if @basedir
      return @basedir
    end

    @basedir = File.join(AppConfig[:shared_storage], "marcao")
    FileUtils.mkdir_p(@basedir)

    @basedir
  end

end
