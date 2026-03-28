%% Requirements-led model + verification matrix
% Aircraft Cabin Pressurisation System (self-contained)

clear; clc; close all;
rng(42); % reproducibility

%% ==========================================================
%  SECTION A — REQUIREMENTS
%  ==========================================================
REQ = table( ...
    ["REQ-01"; "REQ-02"; "REQ-03"; "REQ-04"; "REQ-05"; "REQ-06"], ...
    ["The cabin pressurisation system shall reach CRUISE mode within 750 seconds."; ...
     "The cabin pressurisation system shall end in CRUISE mode under nominal conditions."; ...
     "The system shall not exceed the maximum differential pressure limit under nominal conditions."; ...
     "The system shall declare FAULT when sensor data is unavailable."; ...
     "The system shall flag a timeout condition if cruise conditions are not achieved within 750 seconds."; ...
     "The system shall enter FAULT state under sensor fault conditions."], ...
    ["TimeToCruise_sec"; "IsCruise"; "MaxDiffPressureSafe"; "SensorFaultDetected"; "TimeoutDetected"; "IsFaultState"], ...
    ["<="; "=="; "=="; "=="; "=="; "=="], ...
    [750; 1; 1; 1; 1; 1], ...
    ["SingleRun"; "SingleRun"; "SingleRun"; "SingleRun"; "SingleRun"; "SingleRun"], ...
    ["Performance"; "Functional"; "Safety"; "Fault handling"; "Timeout protection"; "State validation"], ...
    'VariableNames', {'ID','Statement','Metric','Operator','Threshold','Scope','Notes'} ...
);

%% ==========================================================
%  SECTION B — MODEL PARAMETERS
%  ==========================================================
SCEN.name = "Nominal Cabin Pressurisation Design";

% Aircraft profile
SCEN.takeoffAltitude_ft = 1000;          % above this, aircraft is considered airborne
SCEN.cruiseAircraftAlt_ft = 35000;       % target aircraft altitude
SCEN.aircraftClimbRate_ftps = 50;        % aircraft climb rate (ft/s)

% Cabin pressurisation behaviour
SCEN.initialCabinAlt_ft = 0;             % starting cabin altitude
SCEN.targetCabinAlt_ft = 8000;           % cabin altitude at cruise
SCEN.cabinClimbRate_ftps = 10;           % cabin altitude changes more slowly than aircraft altitude
SCEN.pressurisationStartDelay_sec = 0;   % delay for delayed system response scenario

% Safety / logic
SCEN.maxDiffPressure_psi = 8.5;          % maximum allowable differential pressure
SCEN.psiPerFt = 0.00025;                 % simplified conversion from altitude difference to psi
SCEN.timeout_sec = 750;                  % timeout requirement for reaching cruise mode
SCEN.TimeoutDetectedEnabled = false;      

% Variability controls (deterministic)
SCEN.stdAircraftClimbRate_ftps = 0.0;
SCEN.stdCabinClimbRate_ftps = 0.0;

% Fault settings
SCEN.sensorFault = false;                % nominal run = false
SCEN.pRandomFailurePerSec = 0.0;         % nominal run = 0

%% ==========================================================
%  SECTION C — SIMULATION SETTINGS
%  ==========================================================
SIM.N = 1;
SIM.dt = 1.0;            % seconds
SIM.maxTime_sec = 1200;  % simulation cap

%% ==========================================================
%  SECTION C2 — MONTE CARLO SETTINGS
%  ==========================================================
MC.enabled = true;
MC.N = 1000;                 % number of Monte Carlo samples
MC.dt = SIM.dt;
MC.maxTime_sec = SIM.maxTime_sec;

% Uncertainty magnitudes
MC.stdAircraftClimbRate_ftps = 1.0;
MC.stdCabinClimbRate_ftps = 0.8;

%% ==========================================================
%  SECTION D — RUN SCENARIOS
%  ==========================================================
for scen_id = 1:4

    SCEN_CASE = SCEN;
    SCEN_CASE.id = scen_id;
    SCEN_CASE.TimeoutDetectedEnabled = false;   % scenario plots do not go to FAULT on timeout

    switch scen_id
        case 1
            SCEN_CASE.name = "SCEN-01: Normal Operation";
            SCEN_CASE.sensorFault = false;
            SCEN_CASE.sensorFaultStart_sec = inf;
            SCEN_CASE.cabinClimbRate_ftps = 12;
            SCEN_CASE.maxDiffPressure_psi = 8.5;
            SCEN_CASE.isNominal = true;

        case 2
            SCEN_CASE.name = "SCEN-02: Sensor Fault";
            SCEN_CASE.sensorFault = true;          % sensor fault triggered
            SCEN_CASE.sensorFaultStart_sec = 200;
            SCEN_CASE.cabinClimbRate_ftps = 12;
            SCEN_CASE.maxDiffPressure_psi = 8.5;
            SCEN_CASE.isNominal = false;

        case 3
            SCEN_CASE.name = "SCEN-03: Slow Cabin Response";
            SCEN_CASE.sensorFault = false;
            SCEN_CASE.sensorFaultStart_sec = inf;   % no fault triggered
            SCEN_CASE.cabinClimbRate_ftps = 4;      % slower pressurisation
            SCEN_CASE.maxDiffPressure_psi = 8.5;
            SCEN_CASE.isNominal = false;

        case 4
            SCEN_CASE.name = "SCEN-04: Reduced Pressure Limit";
            SCEN_CASE.sensorFault = false;
            SCEN_CASE.sensorFaultStart_sec = inf;   % no sensor fault
            SCEN_CASE.cabinClimbRate_ftps = 12;
            SCEN_CASE.maxDiffPressure_psi = 5.0;    % stricter safety constraint
            SCEN_CASE.isNominal = false;
    end

    out = runSimulation(SCEN_CASE, SIM);

    evidence = struct();
    evidence.TimeToCruise_sec = out.timeToCruise_sec(end);
    evidence.IsCruise = double(out.isCruise(end));
    evidence.TimeoutDetected = double(out.TimeoutDetected(end));
    evidence.MaxDiffPressureSafe = double(out.maxDiffPressure_psi(end) <= SCEN_CASE.maxDiffPressure_psi);
    evidence.SensorFaultDetected = double(SCEN_CASE.sensorFault && out.finalState == "FAULT");
    evidence.FinalState = out.finalState;
    evidence.IsFaultState = double(out.finalState == "FAULT");

    %% ==========================================================
    %  SECTION E — VERIFY REQUIREMENTS
    %  ==========================================================
    if SCEN_CASE.sensorFault
        REQ_ACTIVE = REQ;
    else
        REQ_ACTIVE = REQ(REQ.ID ~= "REQ-06", :);
    end

    [expectedPass, applicable] = buildExpectedResults(REQ_ACTIVE, SCEN_CASE);
    V = verifyRequirements(REQ_ACTIVE, evidence, expectedPass, applicable);

    disp("==========================================================");
    disp(SCEN_CASE.name);
    disp("==========================================================");
    disp("=== Evidence (Simulation Output) ===");
    disp(struct2table(evidence));
    disp("=== Verification Matrix ===");
    disp(V);

    figure('Name', sprintf('Simulation Results - %s', SCEN_CASE.name), ...
           'Position', [100+(scen_id*40), 100+(scen_id*40), 1000, 450]);

    subplot(2,2,1);
    cla;
    hold off;
    plot(out.timeLog, out.aircraftAltLog, 'LineWidth', 1.5);
    hold on;
    plot(out.timeLog, out.cabinAltLog, 'LineWidth', 1.5);
    xlabel('Time (sec)');
    ylabel('Altitude (ft)');
    title(sprintf('Altitude Profile (%s)', SCEN_CASE.name));
    legend('Aircraft Altitude', 'Cabin Altitude', 'Location', 'northwest');
    grid on;

    subplot(2,2,3);
    cla;
    hold off;
    plot(out.timeLog, out.diffPressureLog, 'LineWidth', 1.5);
    hold on;
    yline(SCEN_CASE.maxDiffPressure_psi, '--', 'Pressure Limit');
    xlabel('Time (sec)');
    ylabel('Differential Pressure (psi)');
    title('Differential Pressure');
    grid on;

    subplot(2,2,[2 4]);
    cla;
    hold off;
    stateNumeric = zeros(size(out.stateLog));
    stateNumeric(out.stateLog == "GROUND") = 0;
    stateNumeric(out.stateLog == "PRESSURISING") = 1;
    stateNumeric(out.stateLog == "CRUISE") = 2;
    stateNumeric(out.stateLog == "FAULT") = 3;

    stairs(out.timeLog, stateNumeric, 'LineWidth', 2);
    yticks([0 1 2 3]);
    yticklabels({'GROUND','PRESSURISING','CRUISE','FAULT'});
    xlabel('Time (sec)');
    title('State Transitions');
    ylim([-0.5 3.5]);
    grid on;

    fprintf("\n--- Scenario Summary ---\n");
    fprintf("Scenario: %s\n", SCEN_CASE.name);
    fprintf("TimeToCruise_sec: %.2f\n", evidence.TimeToCruise_sec);
    fprintf("FinalState: %s\n", evidence.FinalState);
    fprintf("IsCruise: %d | TimeoutDetected: %d | MaxDiffPressureSafe: %d | SensorFaultDetected: %d | IsFaultState: %d\n\n", ...
        evidence.IsCruise, evidence.TimeoutDetected, evidence.MaxDiffPressureSafe, evidence.SensorFaultDetected, evidence.IsFaultState);

    % Auto-generated scenario conclusion
    conclusionText = generateScenarioConclusion(SCEN_CASE, evidence, V);
    fprintf("Scenario Conclusion: %s\n\n", conclusionText);

end

%% ==========================================================
%  SECTION F — MONTE CARLO SIMULATION
%  ==========================================================
if MC.enabled

    MC_SCEN = struct([]);

    MC_SCEN(1).name = "Nominal";
    MC_SCEN(1).cabinClimbRate_ftps = 12;
    MC_SCEN(1).maxDiffPressure_psi = 8.5;
    MC_SCEN(1).pressurisationStartDelay_sec = 0;

    MC_SCEN(2).name = "Slow Cabin Response";
    MC_SCEN(2).cabinClimbRate_ftps = 10.5;
    MC_SCEN(2).maxDiffPressure_psi = 8.5;
    MC_SCEN(2).pressurisationStartDelay_sec = 0;

    MC_SCEN(3).name = "Delayed System Initialisation";
    MC_SCEN(3).cabinClimbRate_ftps = 12;
    MC_SCEN(3).maxDiffPressure_psi = 8.5;
    MC_SCEN(3).pressurisationStartDelay_sec = 40;

    MC_SCEN(4).name = "Low Pressure";
    MC_SCEN(4).cabinClimbRate_ftps = 11;
    MC_SCEN(4).maxDiffPressure_psi = 8.5;
    MC_SCEN(4).pressurisationStartDelay_sec = 0;

    mcSummary = table('Size',[numel(MC_SCEN), 5], ...
        'VariableTypes', {'string','double','double','double','double'}, ...
        'VariableNames', {'Scenario','MeanTimeToCruise_sec','PassRate_percent', ...
                      'CruiseSuccessRate_percent','TimeoutRate_percent'});

    figure('Name', 'Monte Carlo Time-to-Cruise Distribution', 'Position', [100 100 1100 500]);
    hold on;

    plotHandles = gobjects(numel(MC_SCEN), 1);
    legendEntries = strings(numel(MC_SCEN), 1);

    xlim([600 850]);
    ylim([0 0.026]);

    % Pass/fail shading
    patch([600 750 750 600], [0 0 0.026 0.026], ...
          [0.85 1.00 0.85], ...
          'FaceAlpha', 0.12, ...
          'EdgeColor', 'none', ...
          'HandleVisibility', 'off');

    patch([750 850 850 750], [0 0 0.026 0.026], ...
          [1.00 0.85 0.85], ...
          'FaceAlpha', 0.12, ...
          'EdgeColor', 'none', ...
          'HandleVisibility', 'off');

    for k = 1:numel(MC_SCEN)
        scenMC = SCEN;
        scenMC.name = MC_SCEN(k).name;
        scenMC.sensorFault = false;
        scenMC.sensorFaultStart_sec = inf;
        scenMC.isNominal = false;
        scenMC.TimeoutDetectedEnabled = false;  % keep Monte Carlo unchanged

        scenMC.cabinClimbRate_ftps = MC_SCEN(k).cabinClimbRate_ftps;
        scenMC.maxDiffPressure_psi = MC_SCEN(k).maxDiffPressure_psi;
        scenMC.pressurisationStartDelay_sec = MC_SCEN(k).pressurisationStartDelay_sec;

        scenMC.stdAircraftClimbRate_ftps = MC.stdAircraftClimbRate_ftps;
        scenMC.stdCabinClimbRate_ftps = MC.stdCabinClimbRate_ftps;

        mcOut = runMonteCarloSimulation(scenMC, MC);

        % Requirement-style pass for REQ-01:
        % must reach CRUISE within the 750 second threshold
        req1Threshold = REQ.Threshold(REQ.ID == "REQ-01");
        req1Pass = (mcOut.timeToCruise_sec <= req1Threshold) & (mcOut.isCruise == 1);

        % Summary statistics
        meanTime = mean(mcOut.timeToCruise_sec, 'omitnan');
        passRate = 100 * mean(req1Pass);
        cruiseRate = 100 * mean(mcOut.isCruise);
        timeoutRate = 100 * mean(mcOut.TimeoutDetected);

        mcSummary.Scenario(k) = MC_SCEN(k).name;
        mcSummary.MeanTimeToCruise_sec(k) = meanTime;
        mcSummary.PassRate_percent(k) = passRate;
        mcSummary.CruiseSuccessRate_percent(k) = cruiseRate;
        mcSummary.TimeoutRate_percent(k) = timeoutRate;

        validTimes = mcOut.timeToCruise_sec(~isnan(mcOut.timeToCruise_sec));

        if numel(validTimes) > 1
            [f, xi] = ksdensity(validTimes);
            plotHandles(k) = plot(xi, f, 'LineWidth', 2);
        else
            plotHandles(k) = plot(validTimes, 0, '.', 'MarkerSize', 12);
        end

        % Mean time line for scenario
        xline(meanTime, ':', ...
            'Color', plotHandles(k).Color, ...
            'LineWidth', 1.5, ...
            'HandleVisibility', 'off');

        legendEntries(k) = sprintf('%s (%.1f%% pass)', MC_SCEN(k).name, passRate);
    end

    % Legend entry for dotted mean lines
    hMean = plot(nan, nan, ':k', 'LineWidth', 1.5);

    % Requirement threshold line
    xline(750, '--', 'Requirement Threshold', ...
        'Color', [1 0.2 0.2], ...
        'LineWidth', 2, ...
        'LabelVerticalAlignment', 'top', ...
        'LabelHorizontalAlignment', 'right');

    xlabel('Time to Cruise / Termination (sec)');
    ylabel('Probability Density');
    title('Monte Carlo Time-to-Cruise Distribution (Including Failed Runs)');

    legendHandles = [plotHandles; hMean];
    legendEntries = [legendEntries; "Mean time (dotted lines)"];
    legend(legendHandles, legendEntries, 'Location', 'northeast');

    xlim([600 850]);
    ylim([0 0.026]);
    grid on;
    hold off;

    disp("==========================================================");
    disp("Monte Carlo Summary");
    disp("==========================================================");
    disp(mcSummary);

    disp("Note: The Monte Carlo plot shows all runs, including successful cruise outcomes and runs that exceeded the 750 second requirement. Pass rate indicates the percentage of runs that reached CRUISE within 750 seconds.");
end

%% ==========================================================
%  Local Functions
%  ==========================================================

function out = runSimulation(scen, SIM)
    N = SIM.N;
    out.timeToCruise_sec = nan(N,1);
    out.isCruise = false(N,1);
    out.TimeoutDetected = false(N,1);
    out.maxDiffPressure_psi = nan(N,1);
    out.finalState = "";

    % Keep final run logs for plotting
    out.timeLog = [];
    out.aircraftAltLog = [];
    out.cabinAltLog = [];
    out.diffPressureLog = [];
    out.stateLog = [];

    for i = 1:N
        [out.isCruise(i), out.timeToCruise_sec(i), out.TimeoutDetected(i), ...
         out.maxDiffPressure_psi(i), timeLog, aircraftAltLog, cabinAltLog, ...
         diffPressureLog, stateLog, finalState] = simulateOneRun(scen, SIM.dt, SIM.maxTime_sec);

        if i == N
            out.timeLog = timeLog;
            out.aircraftAltLog = aircraftAltLog;
            out.cabinAltLog = cabinAltLog;
            out.diffPressureLog = diffPressureLog;
            out.stateLog = stateLog;
            out.finalState = finalState;
        end
    end
end

function mcOut = runMonteCarloSimulation(scen, MC)
    N = MC.N;

    mcOut.timeToCruise_sec = nan(N,1);
    mcOut.isCruise = false(N,1);
    mcOut.TimeoutDetected = false(N,1);
    mcOut.maxDiffPressure_psi = nan(N,1);
    mcOut.finalState = strings(N,1);

    for i = 1:N
        [isCruise, timeToCruise_sec, TimeoutDetected, maxDiffPressure_psi, ...
            ~, ~, ~, ~, ~, finalState] = simulateOneRun(scen, MC.dt, MC.maxTime_sec);

        mcOut.isCruise(i) = isCruise;
        mcOut.timeToCruise_sec(i) = timeToCruise_sec;
        mcOut.TimeoutDetected(i) = TimeoutDetected;
        mcOut.maxDiffPressure_psi(i) = maxDiffPressure_psi;
        mcOut.finalState(i) = finalState;
    end
end

function [isCruise, timeToCruise_sec, TimeoutDetected, maxDiffPressure_psi, ...
          timeLog, aircraftAltLog, cabinAltLog, diffPressureLog, stateLog, finalState] = ...
          simulateOneRun(scen, dt, maxTime_sec)

    state = "GROUND";
    t = 0;

    aircraftAlt_ft = 0;
    cabinAlt_ft = scen.initialCabinAlt_ft;

    TimeoutDetected = false;
    maxDiffPressure_psi = 0;
    timeoutRecorded = false;

    % Draw uncertain parameters
    aircraftClimbRate = max(1, scen.aircraftClimbRate_ftps + randn * scen.stdAircraftClimbRate_ftps);
    cabinClimbRate = max(1, scen.cabinClimbRate_ftps + randn * scen.stdCabinClimbRate_ftps);

    steps = floor(maxTime_sec / dt) + 1;
    timeLog = zeros(steps,1);
    aircraftAltLog = zeros(steps,1);
    cabinAltLog = zeros(steps,1);
    diffPressureLog = zeros(steps,1);
    stateLog = strings(steps,1);

    idx = 0;

    while t < maxTime_sec
        % Random fault hazard
        if rand < scen.pRandomFailurePerSec * dt
            state = "FAULT";
        end

        % Sensor fault (triggered only after the configured start time)
        if scen.sensorFault && t >= scen.sensorFaultStart_sec
            state = "FAULT";
        end

        % Aircraft climbs until cruise altitude
        if aircraftAlt_ft < scen.cruiseAircraftAlt_ft
            aircraftAlt_ft = aircraftAlt_ft + aircraftClimbRate * dt;
        end

        % Calculate differential pressure (simplified)
        diffPressure_psi = max(0, (aircraftAlt_ft - cabinAlt_ft) * scen.psiPerFt);
        maxDiffPressure_psi = max(maxDiffPressure_psi, diffPressure_psi);

        switch state
            case "GROUND"
                if aircraftAlt_ft >= scen.takeoffAltitude_ft
                    state = "PRESSURISING";
                end

            case "PRESSURISING"
                % Cabin altitude rises more slowly than aircraft altitude
                if t >= scen.pressurisationStartDelay_sec
                    if cabinAlt_ft < scen.targetCabinAlt_ft
                        cabinAlt_ft = cabinAlt_ft + cabinClimbRate * dt;
                    end
                end

                % Safety check
                if diffPressure_psi > scen.maxDiffPressure_psi
                    state = "FAULT";

                % Cruise condition
                elseif aircraftAlt_ft >= scen.cruiseAircraftAlt_ft && ...
                    abs(cabinAlt_ft - scen.targetCabinAlt_ft) <= 100
                    state = "CRUISE";
                end

                % Timeout condition
                if t >= scen.timeout_sec && ~timeoutRecorded && state ~= "CRUISE"
                    TimeoutDetected = true;
                    timeoutRecorded = true;

                    if isfield(scen, 'TimeoutDetectedEnabled') && scen.TimeoutDetectedEnabled
                        state = "FAULT";
                    end
                end

            case "CRUISE"
                % Hold state

            case "FAULT"
                % Hold state
        end

        % Record current sample
        idx = idx + 1;
        timeLog(idx) = t;
        aircraftAltLog(idx) = aircraftAlt_ft;
        cabinAltLog(idx) = cabinAlt_ft;
        diffPressureLog(idx) = diffPressure_psi;
        stateLog(idx) = state;

        if state == "CRUISE" || state == "FAULT"
            break;
        end

        t = t + dt;
    end

    timeLog = timeLog(1:idx);
    aircraftAltLog = aircraftAltLog(1:idx);
    cabinAltLog = cabinAltLog(1:idx);
    diffPressureLog = diffPressureLog(1:idx);
    stateLog = stateLog(1:idx);

    finalState = state;
    isCruise = (state == "CRUISE");
    timeToCruise_sec = t;
end

function [expectedPass, applicable] = buildExpectedResults(REQ, scen)
    n = height(REQ);
    expectedPass = false(n,1);
    applicable = true(n,1);

    for i = 1:n
        reqID = REQ.ID(i);

        switch reqID
            case "REQ-01"
                expectedPass(i) = scen.isNominal;
                applicable(i) = true;

            case "REQ-02"
                expectedPass(i) = scen.isNominal;
                applicable(i) = scen.isNominal;

            case "REQ-03"
                expectedPass(i) = scen.isNominal;
                applicable(i) = true;

            case "REQ-04"
                expectedPass(i) = scen.sensorFault;
                applicable(i) = scen.sensorFault;

            case "REQ-05"
                expectedPass(i) = contains(scen.name, "Slow Cabin Response");
                applicable(i) = true;

            case "REQ-06"
                expectedPass(i) = scen.sensorFault;
                applicable(i) = scen.sensorFault;

            otherwise
                expectedPass(i) = false;
                applicable(i) = true;
        end
    end
end

function V = verifyRequirements(REQ, evidence, expectedPass, applicable)
    n = height(REQ);

    Observed = strings(n,1);
    ActualPass = false(n,1);
    ExpectedPass = expectedPass;
    Applicable = applicable;
    Outcome = strings(n,1);

    for i = 1:n
        metricName = REQ.Metric{i};

        if ~isfield(evidence, metricName)
            Observed(i) = "MISSING_METRIC";
            ActualPass(i) = false;
            Outcome(i) = "MISSING_METRIC";
            continue;
        end

        obs = evidence.(metricName);
        Observed(i) = string(obs);

        op = REQ.Operator{i};
        thr = REQ.Threshold(i);

        % Special handling for REQ-01 (must reach cruise AND within time)
        if REQ.ID(i) == "REQ-01"
            ActualPass(i) = (evidence.TimeToCruise_sec <= thr) && (evidence.IsCruise == 1);
        else
            switch op
                case "<="
                    ActualPass(i) = (obs <= thr);
                case "<"
                    ActualPass(i) = (obs < thr);
                case ">="
                    ActualPass(i) = (obs >= thr);
                case ">"
                    ActualPass(i) = (obs > thr);
                case "=="
                    ActualPass(i) = (obs == thr);
                otherwise
                    ActualPass(i) = false;
            end
        end

        % Applicability logic
        if ~Applicable(i)
            Outcome(i) = "NOT_APPLICABLE";
        else
            if ExpectedPass(i) && ActualPass(i)
                Outcome(i) = "PASS";
            elseif ~ExpectedPass(i) && ~ActualPass(i)
                Outcome(i) = "EXPECTED_FAIL";
            elseif ExpectedPass(i) && ~ActualPass(i)
                Outcome(i) = "UNEXPECTED_FAIL";
            elseif ~ExpectedPass(i) && ActualPass(i)
                Outcome(i) = "UNEXPECTED_PASS";
            end
        end
    end

    V = table(REQ.ID, REQ.Statement, REQ.Metric, Observed, REQ.Operator, REQ.Threshold, ...
        Applicable, ExpectedPass, ActualPass, Outcome, REQ.Scope, REQ.Notes, ...
        'VariableNames', {'ReqID','Statement','Metric','Observed','Operator','Threshold','Applicable','ExpectedPass','ActualPass','Outcome','Scope','Notes'});
end

function conclusionText = generateScenarioConclusion(scen, evidence, V)
    nPass = sum(V.Outcome == "PASS");
    nUnexpectedFail = sum(V.Outcome == "UNEXPECTED_FAIL");
    nUnexpectedPass = sum(V.Outcome == "UNEXPECTED_PASS");
    nExpectedFail = sum(V.Outcome == "EXPECTED_FAIL");
    nNotApplicable = sum(V.Outcome == "NOT_APPLICABLE");

    if scen.isNominal
        if evidence.IsCruise == 1 && evidence.TimeoutDetected == 0 && evidence.MaxDiffPressureSafe == 1
            conclusionText = "Nominal scenario passed all key applicable requirements and reached CRUISE state within the required time.";
        else
            conclusionText = "Nominal scenario did not satisfy all key applicable requirements.";
        end

    elseif scen.sensorFault
        if evidence.SensorFaultDetected == 1 && evidence.IsFaultState == 1
            conclusionText = "Sensor fault scenario correctly transitioned to FAULT state and satisfied fault-handling requirements.";
        else
            conclusionText = "Sensor fault scenario did not fully satisfy expected fault-handling behaviour.";
        end

    elseif contains(scen.name, "Slow Cabin Response")
        if evidence.TimeoutDetected == 1
            conclusionText = "Slow cabin response scenario triggered timeout protection as expected.";
        else
            conclusionText = "Slow cabin response scenario did not trigger expected timeout behaviour.";
        end

    elseif contains(scen.name, "Reduced Pressure Limit")
        if evidence.MaxDiffPressureSafe == 0
            conclusionText = "Reduced pressure limit scenario correctly detected safety violation and entered FAULT.";
        else
            conclusionText = "Reduced pressure limit scenario did not trigger expected safety response.";
        end

    else
        conclusionText = "Scenario completed.";
    end

    conclusionText = sprintf('%s Verification outcomes: %d PASS, %d EXPECTED_FAIL, %d UNEXPECTED_FAIL, %d UNEXPECTED_PASS, %d NOT_APPLICABLE.', ...
        conclusionText, nPass, nExpectedFail, nUnexpectedFail, nUnexpectedPass, nNotApplicable);
end