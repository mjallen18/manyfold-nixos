class ModelScanJob < ApplicationJob
  queue_as :default

  def perform(model)
    # For each file in the model, create a part
    model_path = File.join(model.library.path, model.path)
    Dir.open(model_path) do |dir|
      Dir.glob([
        File.join(dir.path, "*.stl"),
        File.join(dir.path, "*.obj"),
        File.join(dir.path, "files", "*.stl"),
        File.join(dir.path, "files", "*.obj")
      ]).each do |filename|
        model.parts.create(filename: filename.gsub(model_path + "/", ""))
      end
    end
    model.autogenerate_tags_from_path!
  end
end
