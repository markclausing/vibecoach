require 'xcodeproj'
project_path = 'AIFitnessCoach.xcodeproj'
project = Xcodeproj::Project.open(project_path)

def check_group(group, path)
  if group.path.nil?
    puts "Warning: Group '#{group.name || group.display_name}' at #{path} has no path!"
  end
  group.groups.each do |subgroup|
    check_group(subgroup, "#{path}/#{group.name || group.display_name}")
  end
end

project.main_group.groups.each do |group|
  check_group(group, group.name || group.display_name)
end
