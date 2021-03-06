% Unit test for grid2fvcom.
%
% DESCRIPTION:
%   Currently checks against a reference data set for the following:
%       - number of nodes in the output
%       - number of elements in the output
%       - number of time steps in the output
%       - range of values in the node arrays
%       - range of values in the element arrays
%
% It uses some NCEP data for the Irish Sea as the base input. This data is
% from January, 2001. This includes an unstructured grid object (Mobj), the
% NCEP forcing data struct (forcing) and a 'known good' result
% (forcing_interp) for comparison against the new result.
%
% Author(s):
%   Pierre Cazenave (Plymouth Marine Laboratory)
%
% Revision history:
%   2013-05-17 First version.
%   2016-06-02 Fix paths to data to load.
%
%==========================================================================

matlabrc
close all
clc

% Set up our test environment.
[base, subname] = fileparts(mfilename('fullpath'));
addpath(fullfile(base, '../../fvcom_prepro'))

load(fullfile(base, '../data/grid2fvcom_data.mat'));

interpfields = {'uwnd', 'vwnd', 'slp', 'nshf', 'nlwrs', 'nswrs', 'P_E', ...
    'Et', 'time', 'lon', 'lat', 'x', 'y'};

% Perform the interpolation using the new routine and check the outputs are
% the same.
forcing_interp_new = grid2fvcom(Mobj, interpfields, forcing);

% Check we have the same number of fields (if we don't, we can't go any
% further).
fnames = fieldnames(forcing_interp);
if length(fnames) ~= length(fieldnames(forcing_interp_new))
    error(['The number of reference struct field names (%d) does', ...
        ' not equal the number in the new struct (%d)'], ...
        length(fnames), length(fieldnames(forcing_interp_new)))
end

%%

results = struct();

for ff = 1:length(fnames)

    results.(fnames{ff}) = struct();

    switch fnames{ff}
        case {'time', 'lon', 'lat', 'x', 'y'}

            results.(fnames{ff}).vectorValues = 'FAIL';

            results.(fnames{ff}).check = ...
                forcing_interp.(fnames{ff}) - forcing_interp_new.(fnames{ff});
            checkDiff = max(results.(fnames{ff}).check) - ...
                min(results.(fnames{ff}).check);
            if checkDiff == 0
                results.(fnames{ff}).vectorValues = 'PASS';
            end

        otherwise

            %--------------------------------------------------------------
            % Set the pass/fail flags for the tests. Assume fail and only
            % change if proven otherwise.
            %--------------------------------------------------------------
            results.(fnames{ff}).nodeNumber = 'FAIL';
            results.(fnames{ff}).numNodeTimes = 'FAIL';
            results.(fnames{ff}).nodeValues = 'FAIL';

            %--------------------------------------------------------------
            % Check we have the same number of points and time steps in the
            % new interpolation as in the original.
            %--------------------------------------------------------------
            [~, results.(fnames{ff}).origNodeTimes] = ...
                size(forcing_interp.(fnames{ff}).node);
            [results.(fnames{ff}).nNodes, ...
                results.(fnames{ff}).nNodeTimes] = ...
                size(forcing_interp_new.(fnames{ff}).node);

            if results.(fnames{ff}).nNodes == Mobj.nVerts
                results.(fnames{ff}).nodeNumber = 'PASS';
            end
            if results.(fnames{ff}).nNodeTimes == ...
                    results.(fnames{ff}).origNodeTimes
                results.(fnames{ff}).numNodeTimes = 'PASS';
            end

            %--------------------------------------------------------------
            % Check the values in the node arrays match the reference
            % values.
            %--------------------------------------------------------------
            results.(fnames{ff}).nodeDiff = ...
                forcing_interp.(fnames{ff}).node - ...
                forcing_interp_new.(fnames{ff}).node;

            results.(fnames{ff}).nodeRange = ...
                max(results.(fnames{ff}).nodeDiff(:));

            if results.(fnames{ff}).nodeRange == 0
                results.(fnames{ff}).nodeValues = 'PASS';
            end
    end
end

%%
%--------------------------------------------------------------------------
% Print a summary of the testing
%--------------------------------------------------------------------------
totalTests = 0;
totalPasses = 0;

for ff = 1:length(fnames)
    resultnames = fieldnames(results.(fnames{ff}));
    numRes = length(resultnames);

    for fi = 1:numRes

        % Skip if the field is not a string (we're only interested in
        % pass/fail really.
        if ~ischar(results.(fnames{ff}).(resultnames{fi}))
            continue
        else
            % Increment the number of tests performed.
            totalTests = totalTests + 1;
        end

        % Get the total number of PASSed tests.
        if strcmp(results.(fnames{ff}).(resultnames{fi}), 'PASS')
            totalPasses = totalPasses + 1;
        end

        S = results.(fnames{ff}).(resultnames{fi});

        switch resultnames{fi}
            case 'vectorValues'
                fprintf('%s %s values test\n', S, fnames{ff})
                if strcmp(S, 'FAIL')
                    fprintf('\tmin/max of %s range: %f, %f\n', ...
                        fnames{ff}, ...
                        min(results.(fnames{ff}).check), ...
                        max(results.(fnames{ff}).check))
                end

            case 'nodeNumber'
                fprintf('%s %s node number test\n', S, fnames{ff})
                if strcmp(S, 'FAIL')
                    fprintf('\toriginal/new number of %s nodes: %d, %d\n', ...
                        fnames{ff}, ...
                        Mobj.nVerts, ...
                        results.(fnames{ff}).nNodes)
                end

            case 'numNodeTimes'
                fprintf('%s %s node time steps test\n', S, fnames{ff})
                if strcmp(S, 'FAIL')
                    fprintf('\toriginal/new number of %s node times: %d, %d\n', ...
                        fnames{ff}, ...
                        results.(fnames{ff}).origNodeTimes, ...
                        results.(fnames{ff}).nNodeTimes)
                end

            case 'nodeValues'
                fprintf('%s %s node values test\n', S, fnames{ff})
                if strcmp(S, 'FAIL')
                    fprintf('\trange of %s node values: %d\n', ...
                        fnames{ff}, ...
                        results.(fnames{ff}).nodeRange)
                end
        end
    end
end

fprintf('\n------------------SUMMARY------------------\n')
fprintf('           %d of %d tests passed', totalPasses, totalTests)
fprintf('\n-------------------------------------------\n')
