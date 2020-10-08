
function make_mask(
    Nside, θpix; 
    edge_padding_deg = 2,
    edge_rounding_deg = 1,
    apodization_deg = 1,
    ptsrc_radius_arcmin = 7, # roughly similar to Story et al. 2015
    num_ptsrcs = typeof(Nside)<:Tuple ? round(Int, Nside[1]*Nside[2]*(θpix/60)^2 * 120/100)  : round(Int,((Nside*θpix)/60)^2 * 120/100) # SPT-like density of sources
    )
     
    deg2npix(x) = round(Int, x/θpix*60)
    arcmin2npix(x) = round(Int, x/θpix)
    
    ptsrc = .!bleed(sim_ptsrcs(Nside, num_ptsrcs), arcmin2npix(ptsrc_radius_arcmin))
    boundary = boundarymask(Nside, deg2npix(edge_padding_deg))
    mask_array = if apodization_deg in (false, 0)
        boundary .& ptsrc
    else
        cos_apod(boundary, deg2npix(apodization_deg), deg2npix(edge_rounding_deg)) .* cos_apod(ptsrc, arcmin2npix(ptsrc_radius_arcmin));
    end
    
    FlatMap(Float32.(mask_array), θpix=θpix)
end

make_mask(::FlatField{<:Flat{Nside,θpix}}; kwargs...) where {Nside,θpix} = make_mask(Nside, θpix; kwargs...)


# all padding/smoothing/etc... quantities below are in units of numbers of pixels

function boundarymask(Nside, pad)
    m = typeof(Nside)<:Tuple ? fill(true,Nside[2],Nside[1]) : fill(true, Nside, Nside)
    m[1:pad,:]          .= false
    m[:,1:pad]          .= false
    m[end-pad+1:end,:]  .= false
    m[:,end-pad+1:end]  .= false
    m
end

function bleed(img, w)
    Nx,Ny = size(img)
    nearest = getfield.(@ondemand(ImageMorphology.feature_transform)(img),:I)
    [norm(nearest[i,j] .- [i,j]) < w for i=1:Nx,j=1:Ny]
end

function cos_apod(img, w, smooth_distance=false)
    Ny,Nx = size(img)
    nearest = getfield.(@ondemand(ImageMorphology.feature_transform)(.!img),:I)
    distance = [norm(nearest[i,j] .- [i,j]) for i=1:Ny,j=1:Nx]
    if smooth_distance!=false
        distance = @ondemand(ImageFiltering.imfilter)(distance, @ondemand(ImageFiltering.Kernel.gaussian)(smooth_distance))
    end
    @. (1-cos(min(distance,w)/w*pi))/2
end

function round_edges(img, w)
    .!(@ondemand(ImageFiltering.imfilter)(img, @ondemand(ImageFiltering.Kernel.gaussian)(w)) .< 0.5)
end

function sim_ptsrcs(Nside,nsources)
    typeof(Nside) <: Tuple ? (Nx, Ny) = Nside : Nx = Ny = Nside
    m = fill(false,Ny,Nx);
    for i=1:nsources
        m[rand(1:Ny),rand(1:Nx)] = true
    end
    m
end
