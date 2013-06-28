%% Auto Grid - An auto-grid algorithm based on an optimal fit
% Matlab Colony Analyzer Toolkit
% Gordon Bean, June 2013

classdef AutoGrid < Closure
   
    properties
        midrows;
        midcols;
        midgriddims;
        minspotsize;
        gridthresholdmethod;
        offsetstep;
        sizestandard;
        dimensions;
        gridspacing;
    end
    
    methods
        
        function this = AutoGrid( varargin )
            this = this@Closure();
            this = default_param( this, ...
                'midRows', [0.4 0.6], ...
                'midCols', [0.4 0.6], ...
                'midGridDims', [8 8], ...
                'minSpotSize', 10, ...
                ...'gridThresholdMethod', MinFrequency('offset', 5), ...
                'gridThresholdMethod', MaxMinMean(), ...
                'offsetStep', 3, ...
                'sizeStandard', [1853 2765], ...
                'dimensions', nan, ...
                'gridspacing', nan, varargin{:} ); 
        end
        
        function grid = closure_method(this, varargin)
            grid = this.fit_grid(varargin{:});
        end
        
        function grid = fit_grid(this, plate)
            % Initialize grid (spacing, dimensions, [r,c] = nan)
            grid = this.initialize_grid(plate);
            
            % Identify grid orientation
            grid = this.estimate_grid_orientation(plate, grid);
            
            % Compute initial placement
            grid = this.compute_initial_placement(plate, grid);
            
            % Compute the linear parameters of the grid
            grid = this.compute_linear_parameters(plate, grid);
            
            % Search for optimal placement
            grid = this.find_optimal_placement(plate, grid);
            
            % Final adjustment
%             grid = adjust_grid( plate, grid, 'numMiddleAdjusts', 0 );
            grid = adjust_grid( plate, grid );
            
            % Sign the package
            grid.info.GridFunction = this;
        end
        
        function grid = initialize_grid(this, plate)
            % Grid spacing
            if ~isnan(this.gridspacing)
                grid.win = this.gridspacing;
            else
                grid.win = estimate_grid_spacing(plate);
            end

            % Grid dimensions
            if ~isnan(this.dimensions)
                grid.dims = this.dimensions;
            else
                grid.dims = estimate_dimensions( plate, grid.win );
            end

            % Initialize grid row and column coordinates
            [grid.r, grid.c] = deal(nan(grid.dims));
        end
        
        function grid = estimate_grid_orientation(this, plate, grid)
            tang = this.sizestandard(1) / this.sizestandard(2);
            ratiofun = @(xp, yp) atan( -(yp - xp*tang)./(yp*tang-xp) );
            [yp xp] = size(plate);

            theta = ratiofun( xp, yp );
            if ( mean(plate(1,floor(end/2):end)) > ...
                    mean(plate(1,1:floor(end/2))) )
                theta = -theta;
            end
            grid.info.theta = theta;
        end
        
        function grid = compute_initial_placement(this, plate, grid)
            % Get 2D window of the middle of the plate
            range = @(a) fix(a(1)):fix(a(2));
            mid = plate( range(size(plate,1)*this.midrows), ...
                range(size(plate,2)*this.midcols) );

            % Determine the threshold for identifying colonies
            itmid = this.gridthresholdmethod.determine_threshold(mid);

            % Find colony locations
            stats = regionprops( imclearborder(mid > itmid), ...
                'area', 'centroid' );
            cents = cat(1, stats.Centroid);
            areas = cat(1, stats.Area);
            cents = cents(areas > this.minspotsize,:);

            % Find the upper-left colony and determine 
            %  it's location in the plate
            [~,mi] = min(sqrt(sum(cents.^2,2)));
            r0 = cents(mi,2) + size(plate,1)*this.midrows(1);
            c0 = cents(mi,1) + size(plate,2)*this.midcols(1);

            % Determine the initial grid positions
            [cc0 rr0] = meshgrid((0:this.midgriddims(2)-1)*grid.win, ...
                (0:this.midgriddims(1)-1)*grid.win);

            % Define the initial grid coordinates (top-left corner of grid)
            ri = (1 : size(rr0,1));
            ci = (1 : size(cc0,2));

            % Set positions of initial grid coordinates
            grid.r(ri,ci) = rr0;
            grid.c(ri,ci) = cc0;

            % Rotate grid according to orientation estimate
            theta = grid.info.theta;
            rotmat = [cos(theta) -sin(theta); sin(theta) cos(theta)];
            val = ~isnan(grid.r);
            tmp = rotmat * [grid.c(val) grid.r(val)]';

            % Set updated (rotated) positions
            grid.r(val) = r0 + tmp(2,:);
            grid.c(val) = c0 + tmp(1,:);
        end
        
        function grid = compute_linear_parameters(this, plate, grid)
            % Adjust - get linear factors
            ri = (1 : this.midgriddims(1));
            ci = (1 : this.midgriddims(2));

            % Define maximum coordinates for fitting
            rie = find(max(grid.r,[],2)+grid.win < size(plate,1),1,'last');
            cie = find(max(grid.c,[],1)+grid.win < size(plate,2),1,'last');

            % Adjust grid
            grid = adjust_grid( plate, grid, ...
                'rowcoords', 1 : min(ri(end),rie),...
                'colcoords', 1:min(ci(end),cie) );
        end
        
        function grid = find_optimal_placement(this, plate, grid)
            % Compute linear indices of grid
            [cc,rr] = meshgrid(1:grid.dims(2), 1:grid.dims(1));
            rtmp = grid.info.fitfunction(rr(:),cc(:)) * ...
                ([0 1 1]' .* grid.factors.row);
            ctmp = grid.info.fitfunction(rr(:),cc(:)) * ...
                ([0 1 1]' .* grid.factors.col);

            rtmp = round(rtmp);
            rtmp = rtmp - min(rtmp(:)) + 1;
            ctmp = round(ctmp);
            ctmp = ctmp - min(ctmp(:)) + 1;
            
            % Get just the border positions
            mid = true(grid.dims);
            mid(3:end-2,3:end-2) = false;
            mid = mid(:);
            gi = sub2ind(size(plate), round(rtmp(mid)), round(ctmp(mid)));

            % Compute offset grid
            roff = 1 : this.offsetstep : ...
                floor(size(plate,1)-ceil(max(rtmp(:))));
            roff = roff - 1;
            
            coff_ = 1 : this.offsetstep : ...
                floor(size(plate,2)-ceil(max(ctmp(:))));
            coff_ = coff_ - 1;
            coff = coff_ * size(plate,1);

            tmpoff = bsxfun(@plus, roff', coff);
            allpos = bsxfun(@plus, tmpoff, permute(gi, [2 3 1]));

            % Find optimal placement
            tmp_plate = plate(:);
            allplate = tmp_plate(allpos);
            clear tmp_plate

            [row col] = ind2sub(size(tmpoff),argmax(in(mean(allplate,3))));

            grid.r(:) = rtmp(:) + roff(row);
            grid.c(:) = ctmp(:) + coff_(col);
%             [rpos, cpos] = ind2sub(size(plate), allpos(row, col,:));
%             grid.r(:) = rpos(:);
%             grid.c(:) = cpos(:);
        end
    end
    
end


