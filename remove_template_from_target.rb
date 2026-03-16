require 'xcodeproj'

project_path = 'AIFitnessCoach.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Iterate over all targets to remove Secrets-template.swift from Compile Sources phase
project.targets.each do |target|
  target.source_build_phase.files_references.each do |file_ref|
    if file_ref.path == 'Secrets-template.swift'
      puts "Removing #{file_ref.path} from target #{target.name}"
      target.source_build_phase.remove_file_reference(file_ref)
    end
  end
end

project.save
puts "Successfully saved project."
