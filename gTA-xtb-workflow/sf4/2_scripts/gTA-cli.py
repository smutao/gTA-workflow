from utils import *
import json
import os
import argparse
import itertools
from pathlib import Path



def obtain_new_circle_center(anchor_point, first_shell_arm_points, reverse_order=False, file_prefix=''):

    # 这里是你的主要代码
    anchor_point = np.array(anchor_point)
    first_shell_arm_points = np.array(first_shell_arm_points)
    if reverse_order:
        first_shell_arm_points = first_shell_arm_points[::-1]
    num_arm = len(first_shell_arm_points)
    assert num_arm >= 2 

    if file_prefix:
        point2molecule(anchor_point, first_shell_arm_points,file_prefix+'start-molecule.xyz')


    # 以 ‘anchor_point’ 为球心， ‘reference_radius’ 为半径，得到一个球面
    # 然后将 ‘first_shell_arm_points’ 上的点沿着向量 ‘first_shell_arm_points[i]-anchor_point’ 投影到这个球面上
    # 相交的点即为 ‘sphere_points’ 
    reference_radius = 2.0 # angstrom 
    sphere_points = []

    for i in range(num_arm):
        dist = np.linalg.norm(first_shell_arm_points[i]-anchor_point)
        sphere_point = anchor_point + (first_shell_arm_points[i]-anchor_point)/dist*reference_radius
        sphere_points.append(sphere_point)

    sphere_points = np.array(sphere_points)
    if file_prefix:
        point2molecule(anchor_point, sphere_points, file_prefix+'start-reference.xyz')


    if num_arm == 2: 
        # use the middle point of 'sphere_points' as the new circle center 
        new_circle_center = (sphere_points[0] + sphere_points[1]) / 2
        if file_prefix:
            point2molecule(anchor_point, sphere_points, file_prefix+'optimized-2.xyz', new_circle_center)
        return new_circle_center

    # if num_arm > 2: 
    sphere_center = np.mean(sphere_points, axis=0) # center of the sphere points
    r = np.linalg.norm(sphere_center - sphere_points[0]) # initial radius of the circle
    norm = sphere_center-anchor_point 
    norm = norm / np.linalg.norm(norm) # initial guess of the normal vector

    direction = determine_rotation_direction(
        points=first_shell_arm_points,
        center_point=anchor_point,
        normal=norm
    )

    print('direction:', direction) 

    initial_guess = np.concatenate([sphere_center, [r, 0.0]]) # was  result.x[0]
    calc_deviation_with_vars = lambda params: calc_deviation(params, anchor_point=anchor_point, sphere_points=sphere_points, direction=direction)


    margin = 4.0  # 给圆心一定的空间

    if direction == 1:
        bounds = [(sphere_center[0]-margin, sphere_center[0]+margin),  
            (sphere_center[1]-margin, sphere_center[1]+margin),
            (sphere_center[2]-margin, sphere_center[2]+margin),
            (0.5*r, 2.5*r),            
            (-2*np.pi, 2*np.pi)]    # 自变量优化的区间
    else:
        bounds = [(sphere_center[0]-margin, sphere_center[0]+margin),  
            (sphere_center[1]-margin, sphere_center[1]+margin),
            (sphere_center[2]-margin, sphere_center[2]+margin),
            (0.5*r, 2.5*r),            
            (-2*np.pi, 2*np.pi)]    # 自变量优化的区间

    result = minimize(calc_deviation_with_vars, initial_guess, bounds=bounds)


    optimized_points = get_optimized_points(result.x[0:3],result.x[3],result.x[4], anchor_point, num_arm, direction)

    print('sphere points:', sphere_points)
    print('optimized points:', optimized_points)
    print('new circle center:', result.x[0:3])

    if file_prefix:
        point2molecule(anchor_point, optimized_points, file_prefix+'optimized-2.xyz', result.x[0:3])

    return result.x[0:3]

    

def validate_transformations(config, json_path):
    """Validate transformation configurations with comprehensive input validation"""
    transformations = config['transformations']
    index_start_from_1 = config['index_start_from']
    
    # === Layer 1: Input source mutual exclusion validation ===
    has_input_sdf = 'input_sdf' in config and config['input_sdf'] is not None
    has_input_xyz = 'input_xyz' in config and config['input_xyz'] is not None
    
    if not has_input_sdf and not has_input_xyz:
        raise ValueError("Configuration must specify either 'input_sdf' or 'input_xyz' field")
    
    if has_input_sdf and has_input_xyz:
        raise ValueError("Configuration cannot specify both 'input_sdf' and 'input_xyz' fields simultaneously. Choose one input source.")
    
    # === Layer 2: XYZ file constraint validation ===
    first_coord_sphere_only = config.get('first_coord_sphere_only', False)
    
    # Get JSON file directory for relative path resolution
    json_dir = Path(json_path).parent
    
    if has_input_xyz:
        if not first_coord_sphere_only:
            raise ValueError("When using 'input_xyz', 'first_coord_sphere_only' must be set to true (XYZ files lack connectivity information)")
        input_file = json_dir / config['input_xyz']
        file_type = 'XYZ'
    elif has_input_sdf:
        input_file = json_dir / config['input_sdf']  
        file_type = 'SDF'
    else:
        # This should not happen due to earlier validation, but added for safety
        raise ValueError("No valid input file configuration found")
    
    # === Layer 3: File existence and format validation ===
    if not input_file.exists():
        raise ValueError(f"{file_type} file not found: {input_file}")
    
    # Check file extension matches declared type
    if has_input_xyz and not str(input_file).lower().endswith('.xyz'):
        raise ValueError(f"File specified in 'input_xyz' should have .xyz extension: {input_file}")
    elif has_input_sdf and not str(input_file).lower().endswith('.sdf'):
        raise ValueError(f"File specified in 'input_sdf' should have .sdf extension: {input_file}")
    
    print(f"Input validation passed: {file_type} file '{input_file.name}', first_coord_sphere_only={first_coord_sphere_only}")
    
    # === Existing transformation validation logic ===
    # Check alias uniqueness
    aliases = [t['alias'] for t in transformations]
    if len(aliases) != len(set(aliases)):
        duplicates = [alias for alias in set(aliases) if aliases.count(alias) > 1]
        raise ValueError(f"Duplicate transformation aliases found: {duplicates}")
    
    # Check atom overlap between different transformation groups (only for SDF with connectivity analysis)
    if len(transformations) > 1 and has_input_sdf and not first_coord_sphere_only:
        adj_matrix = mol2adjmat(str(input_file))
        
        all_affected_atoms = set()
        for i, transformation in enumerate(transformations):
            # Get atoms affected by this transformation
            input_atom_indices = [transformation['anchor_atom'], transformation['arm_atoms']]
            affected_atoms = set(get_connected_fragment(adj_matrix, input_atom_indices, index_start_from_1))
            
            # Check for overlap with previously processed transformations
            overlap = all_affected_atoms.intersection(affected_atoms)
            if overlap:
                raise ValueError(f"Transformation '{transformation['alias']}' affects atoms {sorted(overlap)} which are already affected by previous transformations")
            
            all_affected_atoms.update(affected_atoms)
            print(f"Transformation '{transformation['alias']}' affects {len(affected_atoms)} atoms")
    elif first_coord_sphere_only:
        print(f"First coordination sphere mode: will only rotate arm_atoms specified in transformations")
    
    print(f"Validation passed: {len(transformations)} transformation(s) with unique aliases and appropriate atom selection")

def generate_transformation_combinations(transformations):
    """Generate all combinations of angles across transformation groups"""
    # Extract angle lists from each transformation
    angle_lists = [t['angle'] for t in transformations]
    
    # Generate cartesian product of all angle combinations
    combinations = list(itertools.product(*angle_lists))
    
    print(f"Generated {len(combinations)} combinations from {[len(angles) for angles in angle_lists]} angles per group")
    
    return combinations

def load_config(json_path):
    """Load configuration from JSON file"""
    with open(json_path, 'r') as f:
        config = json.load(f)
    
    # Set default value for first_coord_sphere_only if not specified
    if 'first_coord_sphere_only' not in config:
        config['first_coord_sphere_only'] = False
    
    return config

def get_input_file_info(config, json_path):
    """Get input file path and type from config, resolved relative to JSON file location"""
    json_dir = Path(json_path).parent
    
    if 'input_xyz' in config and config['input_xyz'] is not None:
        return json_dir / config['input_xyz'], 'xyz'
    else:
        return json_dir / config['input_sdf'], 'sdf'


def process_combination(config, transformations, angle_combination, json_path):
    """Process a single combination of angles across all transformation groups"""
    input_file, file_type = get_input_file_info(config, json_path)
    index_start_from_1 = config['index_start_from']
    first_coord_sphere_only = config.get('first_coord_sphere_only', False)
    
    # Create output directories
    main_output_dir, debug_output_dir = create_output_directories(input_file)
    
    # Read original coordinates based on file type
    if file_type == 'xyz':
        element_symbols, coords = read_xyz_coordinates(str(input_file))
    else:  # SDF
        mol = Chem.SDMolSupplier(str(input_file), removeHs=False)[0]
        conf = mol.GetConformer()
        coords = []
        element_symbols = []
        for i in range(mol.GetNumAtoms()):
            pos = conf.GetAtomPosition(i)
            coords.append([pos.x, pos.y, pos.z])
            atom = mol.GetAtomWithIdx(i)
            element_symbols.append(atom.GetSymbol())
        coords = np.array(coords)
    
    # Start with original coordinates
    current_coords = coords.copy()
    
    # Apply each transformation in sequence
    filename_parts = []
    sdf_name = Path(input_file).stem
    
    for transformation, angle_deg in zip(transformations, angle_combination):
        alias = transformation['alias']
        anchor_atom = transformation['anchor_atom']
        arm_atoms = transformation['arm_atoms']
        
        print(f"  Applying {alias}: {angle_deg} degrees")
        
        # Create input atom indices format
        input_atom_indices = [anchor_atom, arm_atoms]
        
        # Get anchor point and arm points from ORIGINAL coordinates
        if file_type == 'xyz':
            anchor_point, first_shell_arm_points = get_anchor_and_arm_coordinates_from_xyz(str(input_file), input_atom_indices, index_start_from_1)
        else:  # SDF
            anchor_point, first_shell_arm_points = get_anchor_and_arm_coordinates(str(input_file), input_atom_indices, index_start_from_1)
        
        # Calculate circle center using original coordinates
        reverse_order = True
        new_circle_center = obtain_new_circle_center(anchor_point, first_shell_arm_points, reverse_order, file_prefix='')
        
        # Get atoms to rotate based on mode
        if first_coord_sphere_only:
            # Only rotate arm atoms
            relevant_atom_indices = arm_atoms
        else:
            # Get molecular connectivity information (only for SDF)
            adj_matrix = mol2adjmat(str(input_file))
            relevant_atom_indices = get_connected_fragment(adj_matrix, input_atom_indices, index_start_from_1)
        
        # Convert angle from degrees to radians
        theta = np.deg2rad(angle_deg)
        
        # Apply rotation to current coordinates
        for idx in relevant_atom_indices:
            # Convert to 0-based indexing
            i = idx - 1 if index_start_from_1 else idx
            # Rotate the point around the axis defined by anchor_point and new_circle_center
            current_coords[i] = Rotate3(anchor_point, current_coords[i], new_circle_center, theta)
        
        # Add to filename
        filename_parts.append(f"{alias}_{angle_deg}deg")
    
    # Create output filename
    if len(filename_parts) == 1:
        # Single transformation: maintain backward compatibility
        output_filename = f"{sdf_name}_{filename_parts[0]}.xyz"
    else:
        # Multiple transformations: combine all parts
        output_filename = f"{sdf_name}_{'_'.join(filename_parts)}.xyz"
    
    output_path = main_output_dir / output_filename
    
    # Write final structure to XYZ file
    with open(output_path, 'w') as f:
        f.write(f"{len(current_coords)}\n")  # Number of atoms
        f.write(f"Structure with transformations: {', '.join([f'{t}={a}°' for t, a in zip([t['alias'] for t in transformations], angle_combination)])}\n")  # Comment line
        for i in range(len(current_coords)):
            symbol = element_symbols[i]
            x, y, z = current_coords[i]
            f.write(f"{symbol:2s} {x:10.6f} {y:10.6f} {z:10.6f}\n")
    
    return output_path

def create_output_directories(sdf_path):
    """Create output directory structure"""
    sdf_name = Path(sdf_path).stem
    input_dir = Path(sdf_path).parent
    
    main_output_dir = input_dir / sdf_name
    debug_output_dir = main_output_dir / 'debug'
    
    main_output_dir.mkdir(exist_ok=True)
    debug_output_dir.mkdir(exist_ok=True)
    
    return main_output_dir, debug_output_dir

def process_single_rotation(coords, element_symbols, anchor_point, new_circle_center, relevant_atom_indices, 
                          index_start_from_1, angle_deg, output_path):
    """Process a single rotation with specific angle"""
    # Convert angle from degrees to radians
    theta = np.deg2rad(angle_deg)
    
    # Create new coordinates by rotating relevant atoms
    new_coords = coords.copy()
    for idx in relevant_atom_indices:
        # Convert to 0-based indexing
        i = idx - 1 if index_start_from_1 else idx
        # Rotate the point around the axis defined by anchor_point and new_circle_center
        new_coords[i] = Rotate3(anchor_point, coords[i], new_circle_center, theta)
    
    # Write new structure to XYZ file
    with open(output_path, 'w') as f:
        f.write(f"{len(new_coords)}\n")  # Number of atoms
        f.write(f"Structure rotated by {angle_deg} degrees\n")  # Comment line
        for i in range(len(new_coords)):
            symbol = element_symbols[i]
            x, y, z = new_coords[i]
            f.write(f"{symbol:2s} {x:10.6f} {y:10.6f} {z:10.6f}\n")
    
    return output_path

def process_transformation_set(config, transformation, json_path):
    """Process a transformation set with multiple angles"""
    # Get configuration parameters
    input_file, file_type = get_input_file_info(config, json_path)
    index_start_from_1 = config['index_start_from']
    first_coord_sphere_only = config.get('first_coord_sphere_only', False)
    
    alias = transformation['alias']
    anchor_atom = transformation['anchor_atom']
    arm_atoms = transformation['arm_atoms']
    angles = transformation['angle']  # Now handle all angles
    
    # Create output directories
    main_output_dir, debug_output_dir = create_output_directories(input_file)
    
    # Create input atom indices format
    input_atom_indices = [anchor_atom, arm_atoms]
    
    print(f"Processing transformation '{alias}' with {len(angles)} angles: {angles}")
    
    # === One-time calculations (shared across all angles) ===
    # Get coordinates based on file type
    if file_type == 'xyz':
        element_symbols, coords = read_xyz_coordinates(str(input_file))
        anchor_point, first_shell_arm_points = get_anchor_and_arm_coordinates_from_xyz(str(input_file), input_atom_indices, index_start_from_1)
    else:  # SDF
        mol = Chem.SDMolSupplier(str(input_file), removeHs=False)[0]
        conf = mol.GetConformer()
        coords = []
        element_symbols = []
        for i in range(mol.GetNumAtoms()):
            pos = conf.GetAtomPosition(i)
            coords.append([pos.x, pos.y, pos.z])
            atom = mol.GetAtomWithIdx(i)
            element_symbols.append(atom.GetSymbol())
        coords = np.array(coords)
        anchor_point, first_shell_arm_points = get_anchor_and_arm_coordinates(str(input_file), input_atom_indices, index_start_from_1)
    
    # Set debug file prefix with alias
    debug_prefix = str(debug_output_dir / f'{alias}_')
    
    reverse_order = True  # Default value, could be added to config later
    
    # Calculate circle center (only once)
    new_circle_center = obtain_new_circle_center(anchor_point, first_shell_arm_points, reverse_order, file_prefix=debug_prefix)
    
    # Get atoms to rotate based on mode
    if first_coord_sphere_only:
        # Only rotate arm atoms
        relevant_atom_indices = arm_atoms
        print(f'First coordination sphere mode: rotating {len(relevant_atom_indices)} arm atoms')
    else:
        # Get molecular connectivity information (only for SDF)
        adj_matrix = mol2adjmat(str(input_file)) 
        num_atom = len(adj_matrix)
        print(f'Number of atoms: {num_atom}')
        relevant_atom_indices = get_connected_fragment(adj_matrix, input_atom_indices, index_start_from_1)
        print(f'Connectivity analysis: rotating {len(relevant_atom_indices)} connected atoms')
    
    # === Process each angle ===
    output_paths = []
    file_name = Path(input_file).stem
    
    for angle_deg in angles:
        print(f"  Processing angle: {angle_deg} degrees")
        
        # Create output filename with file_prefix, alias, and angle
        output_filename = f"{file_name}_{alias}_{angle_deg}deg.xyz"
        output_path = main_output_dir / output_filename
        
        # Process single rotation (always from original coordinates)
        result_path = process_single_rotation(
            coords, element_symbols, anchor_point, new_circle_center, relevant_atom_indices,
            index_start_from_1, angle_deg, output_path
        )
        
        output_paths.append(result_path)
        print(f"    Output written to: {result_path}")
    
    return output_paths

def main():
    """Main function with command line argument support"""
    parser = argparse.ArgumentParser(description='gTA molecular geometry transformation tool')
    parser.add_argument('json_file', nargs='?', default='input/g1-babel-1.json',
                       help='JSON configuration file path')
    
    args = parser.parse_args()
    
    # Load configuration
    try:
        config = load_config(args.json_file)
        print(f"Loaded configuration from: {args.json_file}")
    except Exception as e:
        print(f"Error loading configuration: {e}")
        return
    
    # Validate transformations
    try:
        validate_transformations(config, args.json_file)
    except Exception as e:
        print(f"Validation error: {e}")
        return
    
    transformations = config['transformations']
    
    # Handle single vs multiple transformation groups
    if len(transformations) == 1:
        # Single transformation group: use existing logic for backward compatibility
        print(f"\nProcessing single transformation group: {transformations[0]['alias']}")
        try:
            output_paths = process_transformation_set(config, transformations[0], args.json_file)
            print(f"Successfully processed transformation: {transformations[0]['alias']}")
            print(f"Generated {len(output_paths)} output files")
        except Exception as e:
            print(f"Error processing transformation {transformations[0]['alias']}: {e}")
    
    else:
        # Multiple transformation groups: generate and process combinations
        print(f"\nProcessing {len(transformations)} transformation groups")
        
        # Generate all combinations
        combinations = generate_transformation_combinations(transformations)
        
        # Process each combination
        output_paths = []
        for i, angle_combination in enumerate(combinations):
            print(f"\nProcessing combination {i+1}/{len(combinations)}: {angle_combination}")
            try:
                output_path = process_combination(config, transformations, angle_combination, args.json_file)
                output_paths.append(output_path)
                print(f"  Generated: {output_path.name}")
            except Exception as e:
                print(f"  Error processing combination {angle_combination}: {e}")
        
        print(f"\nSuccessfully generated {len(output_paths)} combination files")
        
        # Also generate individual transformation debug files
        for transformation in transformations:
            try:
                debug_paths = process_transformation_set(config, transformation, args.json_file)
                print(f"Generated debug files for {transformation['alias']}: {len(debug_paths)} files")
            except Exception as e:
                print(f"Error generating debug files for {transformation['alias']}: {e}")

if __name__ == "__main__":
    main()

