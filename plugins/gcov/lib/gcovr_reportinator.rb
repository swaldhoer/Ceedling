require 'reportinator_helper'
require 'ceedling/constants'

class GcovrReportinator

  def initialize(system_objects)
    @ceedling = system_objects
    @reportinator_helper = ReportinatorHelper.new(system_objects)
    support_deprecated_options( @ceedling[:configurator].project_config_hash )
  end

  # Generate the gcovr report(s) specified in the options.
  def make_reports(opts)
    # Get the gcovr version number.
    gcovr_version_info = get_gcovr_version()

    # Build the common gcovr arguments.
    args_common = args_builder_common(opts)

    if ((gcovr_version_info[0] == 4) && (gcovr_version_info[1] >= 2)) || (gcovr_version_info[0] > 4)
      reports = []

      # gcovr version 4.2 and later supports generating multiple reports with a single call.
      args = args_common

      args += (_args = args_builder_cobertura(opts, false))
      reports << "Cobertura XML" if not _args.empty?

      args += (_args = args_builder_sonarqube(opts, false))
      reports << "SonarQube" if not _args.empty?
      
      args += (_args = args_builder_json(opts, true))
      reports << "JSON" if not _args.empty?
      
      # As of gcovr version 4.2, the --html argument must appear last.
      args += (_args = args_builder_html(opts, false))
      reports << "HTML" if not _args.empty?
      
      msg = @ceedling[:reportinator].generate_progress("Creating #{reports.join(', ')} coverage report(s) with gcovr in '#{GCOV_ARTIFACTS_PATH}'")
      @ceedling[:streaminator].stdout_puts("\n" + msg, Verbosity::NORMAL)

      # Generate the report(s).
      # only if one of the previous done checks for:
      #
      # - args_builder_cobertura
      # - args_builder_sonarqube
      # - args_builder_json
      # - args_builder_html
      #
      # updated the args variable. In other case, no need to run GCOVR
      # for current setup.
      if !(args == args_common)
        run(args)
      end
    else
      # gcovr version 4.1 and earlier supports HTML and Cobertura XML reports.
      # It does not support SonarQube and JSON reports.
      # Reports must also be generated separately.
      args_cobertura = args_builder_cobertura(opts, true)
      args_html = args_builder_html(opts, true)

      if args_html.length > 0
        msg = @ceedling[:reportinator].generate_progress("Creating an HTML coverage report with gcovr in '#{GCOV_ARTIFACTS_PATH}'")
        @ceedling[:streaminator].stdout_puts(msg, Verbosity::NORMAL)

        # Generate the HTML report.
        run(args_common + args_html)
      end

      if args_cobertura.length > 0
        msg = @ceedling[:reportinator].generate_progress("Creating an Cobertura XML coverage report with gcovr in '#{GCOV_ARTIFACTS_PATH}'")
        @ceedling[:streaminator].stdout_puts(msg, Verbosity::NORMAL)

        # Generate the Cobertura XML report.
        run(args_common + args_cobertura)
      end
    end

    # Determine if the gcovr text report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::TEXT)
      make_text_report(opts, args_common)
    end
  end


  def support_deprecated_options(opts)
    # Support deprecated :html_report: and ":html_report_type: basic" options.
    if !is_report_enabled(opts, ReportTypes::HTML_BASIC) && (opts[:gcov_html_report] || (opts[:gcov_html_report_type].is_a? String) && (opts[:gcov_html_report_type].casecmp("basic") == 0))
      opts[:gcov_reports].push(ReportTypes::HTML_BASIC)
    end

    # Support deprecated ":html_report_type: detailed" option.
    if !is_report_enabled(opts, ReportTypes::HTML_DETAILED) && (opts[:gcov_html_report_type].is_a? String) && (opts[:gcov_html_report_type].casecmp("detailed") == 0)
      opts[:gcov_reports].push(ReportTypes::HTML_DETAILED)
    end

    # Support deprecated :xml_report: option.
    if opts[:gcov_xml_report]
      opts[:gcov_reports].push(ReportTypes::COBERTURA)
    end

    # Default to HTML basic report when no report types are defined.
    if opts[:gcov_reports].empty? && opts[:gcov_html_report_type].nil? && opts[:gcov_xml_report].nil?
      opts[:gcov_reports] = [ReportTypes::HTML_BASIC]

      msg = <<~TEXT_BLOCK
        NOTE: In your project.yml, define one or more of the following to specify which reports to generate.
        For now, creating only an #{ReportTypes::HTML_BASIC} report...
        
        :gcov:
          :reports:
            - #{ReportTypes::HTML_BASIC}"
            - #{ReportTypes::HTML_DETAILED}"
            - #{ReportTypes::TEXT}"
            - #{ReportTypes::COBERTURA}"
            - #{ReportTypes::SONARQUBE}"
            - #{ReportTypes::JSON}"
  
      TEXT_BLOCK

      @ceedling[:streaminator].stdout_puts(msg, Verbosity::NORMAL)
    end
  end


  private

  GCOVR_SETTING_PREFIX = "gcov_gcovr"

  # Build the gcovr report generation common arguments.
  def args_builder_common(opts)
    gcovr_opts = get_opts(opts)

    args = ""
    args += "--root \"#{gcovr_opts[:report_root] || '.'}\" "
    args += "--config \"#{gcovr_opts[:config_file]}\" " unless gcovr_opts[:config_file].nil?
    args += "--filter \"#{gcovr_opts[:report_include]}\" " unless gcovr_opts[:report_include].nil?
    args += "--exclude \"#{gcovr_opts[:report_exclude] || GCOV_FILTER_EXCLUDE}\" "
    args += "--gcov-filter \"#{gcovr_opts[:gcov_filter]}\" " unless gcovr_opts[:gcov_filter].nil?
    args += "--gcov-exclude \"#{gcovr_opts[:gcov_exclude]}\" " unless gcovr_opts[:gcov_exclude].nil?
    args += "--exclude-directories \"#{gcovr_opts[:exclude_directories]}\" " unless gcovr_opts[:exclude_directories].nil?
    args += "--branches " if gcovr_opts[:branches].nil? || gcovr_opts[:branches] # Defaults to enabled.
    args += "--sort-uncovered " if gcovr_opts[:sort_uncovered]
    args += "--sort-percentage " if gcovr_opts[:sort_percentage].nil? || gcovr_opts[:sort_percentage] # Defaults to enabled.
    args += "--print-summary " if gcovr_opts[:print_summary]
    args += "--gcov-executable \"#{gcovr_opts[:gcov_executable]}\" " unless gcovr_opts[:gcov_executable].nil?
    args += "--exclude-unreachable-branches " if gcovr_opts[:exclude_unreachable_branches]
    args += "--exclude-throw-branches " if gcovr_opts[:exclude_throw_branches]
    args += "--use-gcov-files " if gcovr_opts[:use_gcov_files]
    args += "--gcov-ignore-parse-errors " if gcovr_opts[:gcov_ignore_parse_errors]
    args += "--keep " if gcovr_opts[:keep]
    args += "--delete " if gcovr_opts[:delete]
    args += "-j #{gcovr_opts[:threads]} " if !(gcovr_opts[:threads].nil?) && (gcovr_opts[:threads].is_a? Integer)

    [:fail_under_line, :fail_under_branch, :source_encoding, :object_directory].each do |opt|
      unless gcovr_opts[opt].nil?

        value = gcovr_opts[opt]
        if (opt == :fail_under_line) || (opt == :fail_under_branch)
          if not value.is_a? Integer
            @ceedling[:streaminator].stdout_puts("ERROR: Option value #{opt} has to be an integer", Verbosity::NORMAL)
            value = nil
          elsif (value < 0) || (value > 100)
            @ceedling[:streaminator].stdout_puts("ERROR: Option value #{opt} has to be a percentage from 0 to 100", Verbosity::NORMAL)
            value = nil
          end
        end
        args += "--#{opt.to_s.gsub('_','-')} #{value} " unless value.nil?
      end
    end

    return args
  end


  # Build the gcovr Cobertura XML report generation arguments.
  def args_builder_cobertura(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the Cobertura XML report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::COBERTURA)
      # Determine the Cobertura XML report file name.
      artifacts_file_cobertura = GCOV_ARTIFACTS_FILE_COBERTURA
      if !(gcovr_opts[:cobertura_artifact_filename].nil?)
        artifacts_file_cobertura = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:cobertura_artifact_filename])
      elsif !(gcovr_opts[:xml_artifact_filename].nil?)
        artifacts_file_cobertura = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:xml_artifact_filename])
      end

      args += "--xml-pretty " if gcovr_opts[:xml_pretty] || gcovr_opts[:cobertura_pretty]
      args += "--xml #{use_output_option ? "--output " : ""} \"#{artifacts_file_cobertura}\" "
    end

    return args
  end


  # Build the gcovr SonarQube report generation arguments.
  def args_builder_sonarqube(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the gcovr SonarQube XML report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::SONARQUBE)
      # Determine the SonarQube XML report file name.
      artifacts_file_sonarqube = GCOV_ARTIFACTS_FILE_SONARQUBE
      if !(gcovr_opts[:sonarqube_artifact_filename].nil?)
        artifacts_file_sonarqube = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:sonarqube_artifact_filename])
      end

      args += "--sonarqube #{use_output_option ? "--output " : ""} \"#{artifacts_file_sonarqube}\" "
    end

    return args
  end


  # Build the gcovr JSON report generation arguments.
  def args_builder_json(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the gcovr JSON report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::JSON)
      # Determine the JSON report file name.
      artifacts_file_json = GCOV_ARTIFACTS_FILE_JSON
      if !(gcovr_opts[:json_artifact_filename].nil?)
        artifacts_file_json = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:json_artifact_filename])
      end

      args += "--json-pretty " if gcovr_opts[:json_pretty]
      # Note: In gcovr 4.2, the JSON report is output only when the --output option is specified.
      # Hopefully we can remove --output after a future gcovr release.
      args += "--json #{use_output_option ? "--output " : ""} \"#{artifacts_file_json}\" "
    end

    return args
  end


  # Build the gcovr HTML report generation arguments.
  def args_builder_html(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the gcovr HTML report is enabled. Defaults to enabled.
    html_enabled = (opts[:gcov_html_report].nil? && opts[:gcov_reports].empty?) ||
                   is_report_enabled(opts, ReportTypes::HTML_BASIC) ||
                   is_report_enabled(opts, ReportTypes::HTML_DETAILED)

    if html_enabled
      # Determine the HTML report file name.
      artifacts_file_html = GCOV_ARTIFACTS_FILE_HTML
      if !(gcovr_opts[:html_artifact_filename].nil?)
        artifacts_file_html = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:html_artifact_filename])
      end

      is_html_report_type_detailed = (opts[:gcov_html_report_type].is_a? String) && (opts[:gcov_html_report_type].casecmp("detailed") == 0)

      args += "--html-details " if is_html_report_type_detailed || is_report_enabled(opts, ReportTypes::HTML_DETAILED)
      args += "--html-title \"#{gcovr_opts[:html_title]}\" " unless gcovr_opts[:html_title].nil?
      args += "--html-absolute-paths " if !(gcovr_opts[:html_absolute_paths].nil?) && gcovr_opts[:html_absolute_paths]
      args += "--html-encoding \"#{gcovr_opts[:html_encoding]}\" " unless gcovr_opts[:html_encoding].nil?

      [:html_medium_threshold, :html_high_threshold].each do |opt|
        args += "--#{opt.to_s.gsub('_','-')} #{gcovr_opts[opt]} " unless gcovr_opts[opt].nil?
      end

      # The following option must be appended last for gcovr version <= 4.2 to properly work.
      args += "--html #{use_output_option ? "--output " : ""} \"#{artifacts_file_html}\" "
    end

    return args
  end


  # Generate a gcovr text report.
  def make_text_report(opts, args_common)
    gcovr_opts = get_opts(opts)
    args_text = ""
    message_text = "Creating a text coverage report"

    filename = gcovr_opts[:text_artifact_filename] || 'coverage.txt'

    artifacts_file_txt = File.join(GCOV_ARTIFACTS_PATH, filename)
    args_text += "--output \"#{artifacts_file_txt}\" "
    message_text += " in '#{GCOV_ARTIFACTS_PATH}'"

    msg = @ceedling[:reportinator].generate_progress(message_text)
    @ceedling[:streaminator].stdout_puts(msg, Verbosity::NORMAL)

    # Generate the text report
    run(args_common + args_text)
  end


  # Get the gcovr options from the project options.
  def get_opts(opts)
    return opts[GCOVR_SETTING_PREFIX.to_sym] || {}
  end


  # Run gcovr with the given arguments.
  def run(args)
    command = @ceedling[:tool_executor].build_command_line(TOOLS_GCOV_GCOVR_POST_REPORT, [], args)
    @ceedling[:streaminator].stdout_puts("Command: #{command}", Verbosity::DEBUG)

    command[:options][:boom] = false # Don't raise an exception if non-zero exit
    shell_result = @ceedling[:tool_executor].exec( command )

    @reportinator_helper.print_shell_result(shell_result)
    show_gcovr_message(shell_result[:exit_code])
  end


  # Get the gcovr version number as components.
  # Returns [major, minor].
  def get_gcovr_version()
    version_number_major = 0
    version_number_minor = 0

    command = @ceedling[:tool_executor].build_command_line(TOOLS_GCOV_GCOVR_POST_REPORT, [], "--version")
    @ceedling[:streaminator].stdout_puts("Command: #{command}", Verbosity::DEBUG)

    shell_result = @ceedling[:tool_executor].exec( command )
    version_number_match_data = shell_result[:output].match(/gcovr ([0-9]+)\.([0-9]+)/)

    if !(version_number_match_data.nil?) && !(version_number_match_data[1].nil?) && !(version_number_match_data[2].nil?)
        version_number_major = version_number_match_data[1].to_i
        version_number_minor = version_number_match_data[2].to_i
    end

    return version_number_major, version_number_minor
  end


  # Show a more human-friendly message on gcovr return code
  def show_gcovr_message(exitcode)
    if ((exitcode & 2) == 2)
      @ceedling[:streaminator].stdout_puts("ERROR: Line coverage is less than the minimum", Verbosity::NORMAL)
      raise
    end
    if ((exitcode & 4) == 4)
      @ceedling[:streaminator].stdout_puts("ERROR: Branch coverage is less than the minimum", Verbosity::NORMAL)
      raise
    end
  end


  # Returns true if the given report type is enabled, otherwise returns false.
  def is_report_enabled(opts, report_type)
    return !(opts.nil?) && !(opts[:gcov_reports].nil?) && (opts[:gcov_reports].map(&:upcase).include? report_type.upcase)
  end

end
