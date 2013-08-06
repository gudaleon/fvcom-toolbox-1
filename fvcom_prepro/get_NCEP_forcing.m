function data = get_NCEP_forcing(Mobj, modelTime, varlist)
% Get the required parameters from NCEP OPeNDAP data to force FVCOM
% (through any of Casename_wnd.nc, Casename_sst.nc, Casename_hfx.nc
% or Casename_pre_evap.nc).
%
% data = get_NCEP_forcing(Mobj, modelTime)
%
% DESCRIPTION:
%   Using OPeNDAP, extract the necessary parameters to create an FVCOM
%   forcing file. Requires the air_sea toolbox and the OPeNDAP toolbox (see
%   below for where to get them).
%
% INPUT:
%   Mobj - MATLAB mesh object. Must contain fields:
%       lon, lat    - array of longitude and latitudes.
%       have_lonlat - boolean to signify whether coordinates are spherical
%                   or cartesian.
%   modelTime - Modified Julian Date start and end times
%   varlist [optional] - cell array of data to download from NCEP. Use the
%   NetCDF file prefix (e.g. uwnd, slp etc.).
%
% OUTPUT:
%   data - struct of the data necessary to force FVCOM. These can be
%   interpolated onto an unstructured grid in Mobj using grid2fvcom.m.
%
% The parameters which can be obtained from the NCEP data are:
%     - u wind component (uwnd)
%     - v wind component (vwnd)
%     - Net longwave radiation surface (nlwrs)
%     - Net shortwave radiation surface (nswrs)
%     - Air temperature (air)
%     - Relative humidity (rhum)
%     - Precipitation rate (prate)
%     - Sea level pressure (slp)
%     - Latent heat flux (lhtfl)
%     - Surface heat flux (shtfl)
%     - Potential evaporation rate (pevpr)
%
% In addition to these, the momentum flux is calculated from wind data.
% Precipitation is converted from kg/m^2/s to m/s. Evaporation is
% calculated from the mean daily latent heat net flux (lhtfl) at the
% surface.
%
% EXAMPLE USAGE:
%   To download the default set of data (see list above):
%
%       forcing = get_NCEP_forcing(Mobj, [51345, 51376]);
%
%   To only downloading wind data:
%
%       forcing = get_NCEP_forcing(Mobj, [51345, 51376], {'uwnd', 'vwnd'});
%
% REQUIRES:
%   The air_sea toolbox:
%       http://woodshole.er.usgs.gov/operations/sea-mat/air_sea-html/index.html
%   The OPeNDAP toolbox:
%       http://www.opendap.org/pub/contributed/source/ml-toolbox/
%
% Author(s)
%   Pierre Cazenave (Plymouth Marine Laboratory)
%   Ricardo Torres (Plymouth Marine Laboratory)
%
% Revision history:
%   2012-10-31 First version based on get_NCEP_L4.m.
%   2013-02-14 Add support for the native OPeNDAP functions in the MATLAB
%   netcdf tools. Also fix the value of data.P_E.data to be only the
%   evaporation. The evaporation available from NCEP in prate is in units
%   of W m^{-2} whereas FVCOM expects ms^{-1}. Rather than convert from W
%   m^{-2} to ms^{-1}, use the latent heat flux at the surface with the
%   density of water and the latent heat of vaporisation to estimate
%   evaporation rate in ms^{-1}.
%   2013-06-17 Remove the 'pevpr' variable from the data fetched from NCEP.
%   The 'pevpr' data only covers land (and is therefore largely useless for
%   the toolbox's need. Also, we're not actually using 'pevpr' for the
%   calculation of evaporation since we're estimating that from the latent
%   heat net flux ('lhtfl'), so it's superfluous anyway.
%   2013-06-28 Changed the way the Matlab version is determiend. Now using
%   release date rather then version number. For example version 7.13 >
%   verion 7.7 but 7.13 is not greater than 7.7.
%   2013-07-18 Add support for selecting only a subset of the available
%   variables from NCEP.
%
%==========================================================================

subname = 'get_NCEP_forcing';

% Define date that matlab version 7.14 was released.
% OPeNDAP was included in version 7.14
% see http://en.wikipedia.org/wiki/MATLAB and
% https://publicwiki.deltares.nl/display/OET/OPeNDAP+access+with+Matlab
version_7_14_date = datenum(2012,3,1);
%version_7_13_date = datenum(2011,9,1);

global ftbverbose;
if ftbverbose
    fprintf('\nbegin : %s\n', subname)
end

% Get the extent of the model domain (in spherical)
if ~Mobj.have_lonlat
    error('Need spherical coordinates to extract the forcing data')
else
    % Add a buffer of one grid cell in latitude and two in longitude to
    % make sure the model domain is fully covered by the extracted data.
    [dx, dy] = deal(2.5, 2.5); % approximate NCEP resolution in degrees
    extents = [min(Mobj.lon(:))-(2*dx), max(Mobj.lon(:))+(2*dx), min(Mobj.lat(:))-dy, max(Mobj.lat(:))+dy];
end

if modelTime(end) - modelTime(1) > 365
    error('Can''t (yet) process more than a year at a time.')
end

yearStart = mjulian2greg(modelTime(1));
yearEnd = mjulian2greg(modelTime(end));
if yearEnd ~= yearStart
    error('Can''t (yet) process across a year boundary.')
else
    year = yearEnd;
end

% Set up a struct of the NCEP remote locations in which we're interested.
ncep.uwnd   = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/uwnd.10m.gauss.',num2str(year),'.nc'];
ncep.vwnd   = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/vwnd.10m.gauss.',num2str(year),'.nc'];
ncep.nlwrs  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/nlwrs.sfc.gauss.',num2str(year),'.nc'];
ncep.nswrs  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/nswrs.sfc.gauss.',num2str(year),'.nc'];
ncep.air    = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/air.2m.gauss.',num2str(year),'.nc'];
ncep.rhum   = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface/rhum.sig995.',num2str(year),'.nc'];
ncep.prate  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/prate.sfc.gauss.',num2str(year),'.nc'];
ncep.slp    = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface/slp.',num2str(year),'.nc'];
ncep.lhtfl  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/lhtfl.sfc.gauss.',num2str(year),'.nc'];
ncep.shtfl  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/shtfl.sfc.gauss.',num2str(year),'.nc'];
% ncep.pevpr  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/pevpr.sfc.gauss.',num2str(year),'.nc'];

% The fields below can be used to create the net shortwave and longwave
% fluxes if the data you're using don't include net fluxes. Subtract the
% downward from upward fluxes to get net fluxes.
ncep.dswrf  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/dswrf.sfc.gauss.',num2str(year),'.nc'];
ncep.uswrf  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/uswrf.sfc.gauss.',num2str(year),'.nc'];
ncep.dlwrf  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/dlwrf.sfc.gauss.',num2str(year),'.nc'];
ncep.ulwrf  = ['http://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/ncep.reanalysis/surface_gauss/ulwrf.sfc.gauss.',num2str(year),'.nc'];

fields = fieldnames(ncep);

for aa = 1:length(fields)

    % Skip the downward/upward arrays (most of the time we'll be using the
    % NCEP-provided net values).
    if strcmpi(fields{aa}, 'dswrf') || strcmpi(fields{aa}, 'dlwrf') || strcmpi(fields{aa}, 'uswrf') || strcmpi(fields{aa}, 'ulwrf')
        % But only if we haven't been given a list of variables to fetch.
        if nargin ~= 3
            continue
        end
    end

    % We've been given a list of variables to do, so skip those that aren't
    % in the list.
    if nargin == 3 && max(strcmp(fields{aa}, varlist)) ~= 1
        continue
    end
    
    data.(fields{aa}).data = [];
    data.(fields{aa}).time = [];
    data.(fields{aa}).lat = [];
    data.(fields{aa}).lon = [];
    data_attributes.(fields{aa}) = [];

    % Depending on the MATLAB version, either use the native netcdf
    % libraries to load the OPeNDAP data, otherwise we need the relevant
    % third-party toolbox.
    out = ver('MATLAB');
    if datenum(out.Date) > version_7_14_date % Look at the date rather than the version number

        %ncid_info = ncinfo(ncep.(fields{aa}));
        ncid = netcdf.open(ncep.(fields{aa}));

        % If you don't know what it contains, start by using the
        % 'netcdf.inq' operation:
        %[numdims,numvars,numglobalatts,unlimdimid] = netcdf.inq(ncid);
        varid = netcdf.inqVarID(ncid, 'time');
        data_time.time = netcdf.getVar(ncid, varid, 'double');
        varid = netcdf.inqVarID(ncid, (fields{aa}));

        data_attributes.(fields{aa}).(fields{aa}).scale_factor = ...
            netcdf.getAtt(ncid,varid,'scale_factor','double');
        data_attributes.(fields{aa}).(fields{aa}).add_offset = ...
            netcdf.getAtt(ncid,varid,'add_offset','double');
        varid = netcdf.inqVarID(ncid,'lon');
        data_lon.lon = netcdf.getVar(ncid,varid,'double');
        varid = netcdf.inqVarID(ncid,'lat');
        data_lat.lat = netcdf.getVar(ncid,varid,'double');

        timevec = datevec((data_time.time)/24+365);

    else
        % We'll use the third-party OPeNDAP toolbox.
        data_time = loaddap([ncep.(fields{aa}),'?time']);
        data_attributes.(fields{aa}) = loaddap('-A',[ncep.(fields{aa})]);
        timevec = datevec((data_time.time)/24+365);

        % Clip the data to the model domain
        data_lon = loaddap([ncep.(fields{aa}),'?lon']);
        % If the extents are negative in longitude, we need to extract the NCEP
        data_lat = loaddap([ncep.(fields{aa}),'?lat']);
    end

    % Get the data time and convert to Modified Julian Day.
    data.time = greg2mjulian(timevec(:,1), timevec(:,2), timevec(:,3), ...
        timevec(:,4), timevec(:,5), timevec(:,6));
    % Clip the time to the given range
    data_time_mask = data.time >= modelTime(1) & data.time <= modelTime(end);
    data_time_idx = 1:size(data.time,1);
    data_time_idx = data_time_idx(data_time_mask);
    data.time = data.time(data_time_mask);

    % Check the times
    %[yyyy,mm,dd,hh,MM,ss] = mjulian2greg(data.time(1))
    %[yyyy,mm,dd,hh,MM,ss] = mjulian2greg(data.time(end))
    % Get the data in two goes, once for the end of the grid (west of
    % Greenwich), once for the beginning (east of Greenwich), and then
    % stick the two bits together.
    clear index_lon index_lat
    if extents(1) < 0 && extents(2) < 0
        % This is OK, we can just shunt the values by 360.
        extents(1) = extents(1) + 360;
        extents(2) = extents(2) + 360;
        index_lon = find(data_lon.lon > extents(1) & data_lon.lon < extents(2));
    elseif extents(1) < 0 && extents(2) > 0
        % This is the tricky one. We'll do two passes to extract the
        % western chunk first (extents(1)+360 to 360), then the eastern
        % chunk (0-extents(2))
        index_lon{1} = find(data_lon.lon >= extents(1) + 360);
        index_lon{2} = find(data_lon.lon <= extents(2));
    else
        % Dead easy, we're in the eastern hemisphere, so nothing too
        % strenuous here
        index_lon = find(data_lon.lon > extents(1) & data_lon.lon < extents(2));
    end

    % Latitude is much more straightforward
    index_lat = find(data_lat.lat > extents(3) & data_lat.lat < extents(4));
    data.(fields{aa}).lat = data_lat.lat(index_lat);

    % Get the data
    if iscell(index_lon)
        data.(fields{aa}).lon = data_lon.lon(cat(1,index_lon{:}));

        % We need to do each half and merge them
        if datenum(out.Date) > version_7_14_date % Look at the date rather than the version number
            % varidlon = netcdf.inqVarID(ncid,'lon');
            % varidtime = netcdf.inqVarID(ncid,'time');
            % varidlat = netcdf.inqVarID(ncid,'lat');

            varid = netcdf.inqVarID(ncid,(fields{aa}));
            % [varname,xtype,dimids,natts] = netcdf.inqVar(ncid,varid);
            % [~,length1] = netcdf.inqDim(ncid,dimids(1))
            % [~,length2] = netcdf.inqDim(ncid,dimids(2))
            % [~,length3] = netcdf.inqDim(ncid,dimids(3))
            start=[min(index_lon{1})-1,min(index_lat)-1,min(data_time_idx)-1];
            count=[length(index_lon{1}),length(index_lat),length(data_time_idx)];
            data1_west.(fields{aa}).(fields{aa}) = netcdf.getVar(ncid,varid,start,count,'double');
            start=[min(index_lon{2})-1,min(index_lat)-1,min(data_time_idx)-1];
            count=[length(index_lon{2}),length(index_lat),length(data_time_idx)];
            data1_east.(fields{aa}).(fields{aa}) = netcdf.getVar(ncid,varid,start,count,'double');
            data1.(fields{aa}).(fields{aa}).(fields{aa})=cat(1,data1_west.(fields{aa}).(fields{aa}), data1_east.(fields{aa}).(fields{aa}));

        else
            eval(['data1_west.(fields{aa}) = loaddap(''', ncep.(fields{aa}),'?',...
                fields{aa},'[', num2str(min(data_time_idx)-1),':',...
                num2str(max(data_time_idx)-1), '][',...
                num2str(min(index_lat)-1), ':', num2str(max(index_lat)-1),...
                '][', num2str(min(index_lon{1})-1), ':',...
                num2str(length(data_lon.lon)-1), ']'');']);
            eval(['data1_east.(fields{aa}) = loaddap(''', ncep.(fields{aa}),'?',...
                fields{aa}, '[', num2str(min(data_time_idx)-1),':',...
                num2str(max(data_time_idx)-1), '][',...
                num2str(min(index_lat)-1), ':', num2str(max(index_lat)-1),...
                '][', '0', ':', num2str(max(index_lon{2})-1), ']'');']);

            % Merge the two sets of data together
            structfields = fieldnames(data1_west.(fields{aa}).(fields{aa}));
            for ii=1:length(structfields)
                switch structfields{ii}
                    case 'lon'
                        % Only the longitude and the actual data need
                        % sticking together, but each must be done along a
                        % different axis (lon is a vector, the data is an
                        % array).
                        data1.(fields{aa}).(fields{aa}).(structfields{ii}) = ...
                            [data1_west.(fields{aa}).(fields{aa}).(structfields{ii});data1_east.(fields{aa}).(fields{aa}).(structfields{ii})];
                    case fields{aa}
                        % This is the actual data
                        data1.(fields{aa}).(fields{aa}).(structfields{ii}) = ...
                            [data1_west.(fields{aa}).(fields{aa}).(structfields{ii}),data1_east.(fields{aa}).(fields{aa}).(structfields{ii})];
                    otherwise
                        % Assume the data are the same in both arrays. A
                        % simple check of the range of values in the
                        % difference between the two arrays should show
                        % whether they're the same or not. If they are, use
                        % the western values, otherwise, warn about the
                        % differences. It might be the data are relatively
                        % unimportant anyway (i.e. not used later on).
                        try
                            tdata = data1_west.(fields{aa}).(fields{aa}).(structfields{ii}) - data1_east.(fields{aa}).(fields{aa}).(structfields{ii});
                            if range(tdata(:)) == 0
                                % They're the same data
                                data1.(fields{aa}).(fields{aa}).(structfields{ii}) = ...
                                    data1_west.(fields{aa}).(fields{aa}).(structfields{ii});
                            else
                                warning('Unexpected data field and the west and east halves don''t match. Skipping.')
                            end
                        catch
                            warning('Unexpected data field and the west and east halves don''t match. Skipping.')
                        end
                        clear tdata
                end
            end
        end
    else
        % We have a straightforward data extraction
        data.(fields{aa}).lon = data_lon.lon(index_lon);

        if datenum(out.Date) > version_7_14_date % Look at the date rather than the version number
            varid = netcdf.inqVarID(ncid,(fields{aa}));
            % [varname,xtype,dimids,natts] = netcdf.inqVar(ncid,varid);
            % [~,length1] = netcdf.inqDim(ncid,dimids(1))
            % [~,length2] = netcdf.inqDim(ncid,dimids(2))
            % [~,length3] = netcdf.inqDim(ncid,dimids(3))
            start=[min(index_lon)-1,min(index_lat)-1,min(data_time_idx)-1];
            count=[length(index_lon),length(index_lat),length(data_time_idx)];
            data1.(fields{aa}).(fields{aa}).(fields{aa}) = netcdf.getVar(ncid,varid,start,count,'double');

        else
            eval(['data1.(fields{aa}) = loaddap(''', ncep.(fields{aa}),'?',...
                fields{aa}, '[', num2str(min(data_time_idx)-1),':',...
                num2str(max(data_time_idx)-1), '][',...
                num2str(min(index_lat)-1), ':', num2str(max(index_lat)-1),...
                '][', num2str(min(index_lon)-1), ':',...
                num2str(max(index_lon)-1), ']'');']);
        end
    end

    datatmp = squeeze(data1.(fields{aa}).(fields{aa}).(fields{aa}));
    datatmp = (datatmp * data_attributes.(fields{aa}).(fields{aa}).scale_factor) + data_attributes.(fields{aa}).(fields{aa}).add_offset;

    data.(fields{aa}).data = datatmp;
    data.(fields{aa}).time = data.time;
    %     data.(fields{aa}).time = cat(1, data.(fields{aa}).time, squeeze(data1.(fields{aa}).(fields{aa}).time));
    %     data.(fields{aa}).lat = squeeze(data1.(fields{aa}).(fields{aa}).lat);
    %     data.(fields{aa}).lon = squeeze(data1.(fields{aa}).(fields{aa}).lon);

    % Replace values outside the specified actual range with NaNs. For the
    % majority of the variables, this shouldn't ever really generate values
    % of NaN since the coverage is global (land and sea). This did crop up
    % as a problem with the pevpr data (which is land only). In some ways,
    % if something fails later on (e.g. the interpolation) because there's
    % NaNs, that should be a wakeup call to check what's going on with the
    % data.
    if isfield(data_attributes.(fields{aa}).(fields{aa}), 'actual_range')
        actual_min = data_attributes.(fields{aa}).(fields{aa}).actual_range(1);
        actual_max = data_attributes.(fields{aa}).(fields{aa}).actual_range(2);
        mask = data.(fields{aa}).data < actual_min | data.(fields{aa}).data > actual_max;
        data.(fields{aa}).data(mask) = NaN;
    end
end

% Now we have some data, we need to create some additional parameters
% required by FVCOM.

% FVCOM's sign convention is the opposite of the NCEP data for heat fluxes
% (FVCOM: positive = downward flux = ocean heating, negative = upward flux
% = ocean cooling. NCEP: positive = upward flux = ocean cooling, negative =
% downward flux = ocean heating). So, rather than do the corrections in
% create_files.m or wherever, do them here instead.
% data.nlwrs.data = -data.nlwrs.data;
% data.nswrs.data = -data.nswrs.data;

% Convert precipitation from kg/m^2/s to m/s (required by FVCOM) by
% dividing by freshwater density (kg/m^3).
if isfield(data, 'prate')
    data.prate.data = data.prate.data/1000;
end

% Evaporation can be approximated by:
%
%   E(m/s) = lhtfl/Llv/rho
%
% where:
%
%   lhtfl   = "Mean daily latent heat net flux at the surface"
%   Llv     = Latent heat of vaporization (approx to 2.5*10^6 J kg^-1)
%   rho     = 1025 kg/m^3
%
if isfield(data, 'prate')
    Llv = 2.5*10^6;
    rho = 1025; % using a typical value for seawater.
    Et = data.lhtfl.data/Llv/rho;
    data.P_E.data = data.prate.data - Et;
    % Evaporation and precipitation need to have the same sign for FVCOM (ocean
    % losing water is negative in both instances). So, flip the evaporation
    % here.
    data.Et.data = -Et;
end

% Calculate the momentum flux
if isfield(data, 'uwnd') && isfield(data, 'vwnd')
    WW = data.uwnd.data + data.vwnd.data * 1i;
    data.tau.data = stresslp(abs(WW),10);
    [data.tx.data,data.ty.data] = wstress(data.uwnd.data,data.vwnd.data,10);
    data.tx.data=reshape(data.tx.data*0.1, size(data.uwnd.data)); % dyn/cm^2 to N/m^2
    data.ty.data=reshape(data.ty.data*0.1, size(data.uwnd.data)); % dyn/cm^2 to N/m^2
end

% Get the fields we need for the subsequent interpolation
if nargin == 3
    data.lon = data.(varlist{1}).lon;
    data.lon(data.lon > 180) = data.lon(data.lon > 180) - 360;
    data.lat = data.(varlist{1}).lat;
else
    data.lon = data.(fields{1}).lon;
    data.lon(data.lon > 180) = data.lon(data.lon > 180) - 360;
    data.lat = data.(fields{1}).lat;
end

% Convert temperature to degrees Celsius (from Kelvin)
if isfield(data, 'air')
    data.air.data = data.air.data - 273.15;
end

% Have a look at some data.
% [X, Y] = meshgrid(data.lon, data.lat);
% for i=1:size(data.uwnd.data, 3)
%     figure(1)
%     clf
%     uv = sqrt(data.uwnd.data(:, :, i).^2 + data.vwnd.data(:, :, i).^2);
%     pcolor(X, Y, uv)
%     shading flat
%     axis('equal','tight')
%     pause(0.1)
% end

if ftbverbose
    fprintf(['end   : ' subname '\n'])
end

return
