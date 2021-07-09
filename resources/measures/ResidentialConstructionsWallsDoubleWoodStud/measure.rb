# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

resources_path = File.absolute_path(File.join(File.dirname(__FILE__), '../HPXMLtoOpenStudio/resources'))
unless File.exist? resources_path
  resources_path = File.join(OpenStudio::BCLMeasure::userMeasuresDir.to_s, 'HPXMLtoOpenStudio/resources') # Hack to run measures in the OS App since applied measures are copied off into a temporary directory
end
require File.join(resources_path, 'util')
require File.join(resources_path, 'constants')
require File.join(resources_path, 'geometry')
require File.join(resources_path, 'constructions')

# start the measure
class ProcessConstructionsWallsDoubleWoodStud < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Set Residential Walls - Double Wood Stud Construction'
  end

  def description
    return "This measure assigns a double wood stud construction to above-grade walls.#{Constants.WorkflowDescription}"
  end

  def modeler_description
    return 'Calculates and assigns material layer properties of double wood stud constructions for 1) exterior walls of finished spaces, 2) exterior walls (e.g. gable walls) of unfinished attics under roof insulation, and 3) interior walls (e.g., attic knee walls) between finished and unfinished spaces. Adds furniture & partition wall mass. Uninsulated constructions will also be assigned to 1) exterior walls of unfinished spaces, 2) interior walls between finished spaces, and 3) interior walls between unfinished spaces. Any existing constructions for these surfaces will be removed.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make a double argument for nominal R-value of installed cavity insulation
    cavity_r = OpenStudio::Measure::OSArgument::makeDoubleArgument('cavity_r', true)
    cavity_r.setDisplayName('Cavity Insulation Nominal R-value')
    cavity_r.setUnits('hr-ft^2-R/Btu')
    cavity_r.setDescription('Refers to the R-value of the cavity insulation and not the overall R-value of the assembly.')
    cavity_r.setDefaultValue(33.0)
    args << cavity_r

    # make a choice argument for wall cavity insulation installation grade
    installgrade_display_names = OpenStudio::StringVector.new
    installgrade_display_names << '1'
    installgrade_display_names << '2'
    installgrade_display_names << '3'
    install_grade = OpenStudio::Measure::OSArgument::makeChoiceArgument('install_grade', installgrade_display_names, true)
    install_grade.setDisplayName('Cavity Install Grade')
    install_grade.setDescription('Installation grade as defined by RESNET standard. 5% of the cavity is considered missing insulation for Grade 3, 2% for Grade 2, and 0% for Grade 1.')
    install_grade.setDefaultValue('1')
    args << install_grade

    # make a double argument for stud depth
    stud_depth_in = OpenStudio::Measure::OSArgument::makeDoubleArgument('stud_depth_in', true)
    stud_depth_in.setDisplayName('Stud Depth')
    stud_depth_in.setUnits('in')
    stud_depth_in.setDescription('Depth of the studs. 3.5" for 2x4s, 5.5" for 2x6s, etc. The total cavity depth of the double stud wall = (2 x stud depth) + gap depth.')
    stud_depth_in.setDefaultValue('3.5')
    args << stud_depth_in

    # make a double argument for gap depth
    gap_depth_in = OpenStudio::Measure::OSArgument::makeDoubleArgument('gap_depth_in', true)
    gap_depth_in.setDisplayName('Gap Depth')
    gap_depth_in.setUnits('in')
    gap_depth_in.setDescription('Depth of the gap between walls.')
    gap_depth_in.setDefaultValue(3.5)
    args << gap_depth_in

    # make a double argument for framing factor
    framing_factor = OpenStudio::Measure::OSArgument::makeDoubleArgument('framing_factor', true)
    framing_factor.setDisplayName('Framing Factor')
    framing_factor.setUnits('frac')
    framing_factor.setDescription('The fraction of a wall assembly that is comprised of structural framing for the individual (inner and outer) stud walls.')
    framing_factor.setDefaultValue('0.22')
    args << framing_factor

    # make a double argument for framing spacing
    framing_spacing = OpenStudio::Measure::OSArgument::makeDoubleArgument('framing_spacing', true)
    framing_spacing.setDisplayName('Framing Spacing')
    framing_spacing.setUnits('in')
    framing_spacing.setDescription('The on-center spacing between framing in a wall assembly.')
    framing_spacing.setDefaultValue('24')
    args << framing_spacing

    # make a bool argument for staggering of studs
    is_staggered = OpenStudio::Measure::OSArgument::makeBoolArgument('is_staggered', true)
    is_staggered.setDisplayName('Staggered Studs')
    is_staggered.setDescription('Indicates that the double studs are aligned in a staggered fashion (as opposed to being center).')
    is_staggered.setDefaultValue(false)
    args << is_staggered

    # make a double argument for drywall thickness
    drywall_thick_in = OpenStudio::Measure::OSArgument::makeDoubleArgument('drywall_thick_in', true)
    drywall_thick_in.setDisplayName('Drywall Thickness')
    drywall_thick_in.setUnits('in')
    drywall_thick_in.setDescription('Thickness of the drywall material.')
    drywall_thick_in.setDefaultValue(0.5)
    args << drywall_thick_in

    # make a double argument for OSB/Plywood Thickness
    osb_thick_in = OpenStudio::Measure::OSArgument::makeDoubleArgument('osb_thick_in', true)
    osb_thick_in.setDisplayName('OSB/Plywood Thickness')
    osb_thick_in.setUnits('in')
    osb_thick_in.setDescription("Specifies the thickness of the walls' OSB/plywood sheathing. Enter 0 for no sheathing (if the wall has other means to handle the shear load on the wall such as cross-bracing).")
    osb_thick_in.setDefaultValue(0.5)
    args << osb_thick_in

    # make a double argument for Rigid Insulation R-value
    rigid_r = OpenStudio::Measure::OSArgument::makeDoubleArgument('rigid_r', true)
    rigid_r.setDisplayName('Continuous Insulation Nominal R-value')
    rigid_r.setUnits('h-ft^2-R/Btu')
    rigid_r.setDescription('The R-value of the continuous insulation.')
    rigid_r.setDefaultValue(0.0)
    args << rigid_r

    # make a choice argument for exterior finish material
    finishes = OpenStudio::StringVector.new
    WallConstructions.get_exterior_finish_materials.each do |mat|
      finishes << mat.name
    end
    exterior_finish = OpenStudio::Measure::OSArgument::makeChoiceArgument('exterior_finish', finishes, true)
    exterior_finish.setDisplayName('Exterior Finish')
    exterior_finish.setDescription('The exterior finish material.')
    exterior_finish.setDefaultValue(Material.ExtFinishVinylLight.name)
    args << exterior_finish

    return args
  end # end the arguments method

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    walls_by_type = SurfaceTypes.get_walls(model, runner)

    # Get inputs
    cavity_r = runner.getDoubleArgumentValue('cavity_r', user_arguments)
    install_grade = runner.getStringArgumentValue('install_grade', user_arguments).to_i
    stud_depth_in = runner.getDoubleArgumentValue('stud_depth_in', user_arguments)
    gap_depth_in = runner.getDoubleArgumentValue('gap_depth_in', user_arguments)
    framing_factor = runner.getDoubleArgumentValue('framing_factor', user_arguments)
    framing_spacing = runner.getDoubleArgumentValue('framing_spacing', user_arguments)
    is_staggered = runner.getBoolArgumentValue('is_staggered', user_arguments)
    drywall_thick_in = runner.getDoubleArgumentValue('drywall_thick_in', user_arguments)
    osb_thick_in = runner.getDoubleArgumentValue('osb_thick_in', user_arguments)
    rigid_r = runner.getDoubleArgumentValue('rigid_r', user_arguments)
    mat_ext_finish = WallConstructions.get_exterior_finish_material(runner.getStringArgumentValue('exterior_finish', user_arguments))

    if mat_ext_finish.name.include?("None")
      runner.registerError("Double wood stud walls cannot have a 'None' exterior finish")
      return false
    end

    # Apply constructions
    if not WallConstructions.apply_double_stud(runner, model,
                                               walls_by_type[Constants.SurfaceTypeWallExtInsFin],
                                               Constants.SurfaceTypeWallExtInsFin,
                                               cavity_r, install_grade, stud_depth_in, gap_depth_in,
                                               framing_factor, framing_spacing, is_staggered,
                                               drywall_thick_in, osb_thick_in, rigid_r,
                                               mat_ext_finish)
      return false
    end

    if not WallConstructions.apply_double_stud(runner, model,
                                               walls_by_type[Constants.SurfaceTypeWallExtInsUnfin],
                                               Constants.SurfaceTypeWallExtInsUnfin,
                                               cavity_r, install_grade, stud_depth_in, gap_depth_in,
                                               framing_factor, framing_spacing, is_staggered,
                                               0, osb_thick_in, rigid_r,
                                               mat_ext_finish)
      return false
    end

    if not WallConstructions.apply_double_stud(runner, model,
                                               walls_by_type[Constants.SurfaceTypeWallIntFinInsUnfin],
                                               Constants.SurfaceTypeWallIntFinInsUnfin,
                                               cavity_r, install_grade, stud_depth_in, gap_depth_in,
                                               framing_factor, framing_spacing, is_staggered,
                                               0, osb_thick_in, rigid_r,
                                               nil)
      return false
    end

    if not WallConstructions.apply_uninsulated(runner, model, walls_by_type,
                                               osb_thick_in, drywall_thick_in, mat_ext_finish)
      return false
    end

    if not ThermalMassConstructions.apply(runner, model, walls_by_type,
                                          drywall_thick_in)
      return false
    end

    # Remove any constructions/materials that aren't used
    HelperMethods.remove_unused_constructions_and_materials(model, runner)

    return true
  end # end the run method
end # end the measure

# this allows the measure to be use by the application
ProcessConstructionsWallsDoubleWoodStud.new.registerWithApplication
