class MarcAOExporter

  def self.run
    start = Time.now

    Log.info("MARC AO Exporter running")

    res_ids = UserDefined.filter(AppConfig[:marcao_flag_field].intern => 1).filter(Sequel.~(:resource_id => nil)).select(:resource_id).all.map{|r| r[:resource_id]}

    ao_ds = ArchivalObject.any_repo.filter(:root_record_id => res_ids)

    if FileTest.exists?(export_file_path)
      mtime = File.new(export_file_path).mtime
      ao_ds = ao_ds.where{system_mtime > mtime}
    end

    ao_jsons = []

    ao_ds.all.group_by(&:repo_id).each do |repo_id, aos|
      RequestContext.open(:repo_id => repo_id) do
        ao_jsons += URIResolver.resolve_references(ArchivalObject.sequel_to_jsonmodel(aos), MarcAOMapper.resolves)
      end
    end

    File.open(export_file_path, 'w') do |fh|
      fh.write(MarcAOMapper.collection_to_marc(ao_jsons))
    end

    {
      :status => 'ok',
      :export_started_at => start,
      :export_completed_at => Time.now,
      :export_file => export_file_path,
      :resource_ids_selected => res_ids.join(','),
      :archival_objects_exported => ao_jsons.length,
    }
  end

  def self.export_file_path
    File.join(basedir, 'marcao_export.xml')
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