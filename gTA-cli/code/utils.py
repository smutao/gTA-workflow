import numpy as np
from scipy.optimize import minimize
#import matplotlib.pyplot as plt
from rdkit import Chem
from math import pi ,sin, cos, sqrt

def point2molecule(central_point, sphere_points, filename, circle_center = None):
    # 将两组点的坐标转化成XYZ分子文件
    # central_point: 中心点坐标 - 用 C 原子
    # sphere_points: 球面上的点 - 用 H 原子
    # circle_center: 圆心坐标 - 用 O 原子
    # filename: 输出文件名

    assert len(central_point) == 3
    num_atom = 1 + len(sphere_points) 
    if circle_center is not None:
        assert len(circle_center) == 3
        num_atom += 1
    xyz_string = "{:4d}\n\n".format(num_atom)
    xyz_string += "C {:12.6f} {:12.6f} {:12.6f} \n".format(*central_point)
    for i in range(len(sphere_points)):
        xyz_string += "H {:12.6f} {:12.6f} {:12.6f} \n".format(*sphere_points[i])
    if circle_center is not None:
        xyz_string += "O {:12.6f} {:12.6f} {:12.6f} \n".format(*circle_center)

    with open(filename, 'w') as f:
        f.write(xyz_string)

    return 


def get_polygon_points(norm, center, r, num_gon, phi):
    # 给定圆面的方向norm，圆心center，半径r，多边形的顶点数num_gon，以及旋转角度phi
    # 返回多边形的顶点坐标  

    v1 = [-norm[1], norm[0], 0]
    v2 = np.cross(norm, v1)

    v1 = v1 / np.linalg.norm(v1)
    v2 = v2 / np.linalg.norm(v2)

    points = []
    for i in range(num_gon):
        x = center[0] + r* (np.cos(i*2*np.pi/num_gon+phi)*v1[0] + np.sin(i*2*np.pi/num_gon+phi)*v2[0])
        y = center[1] + r* (np.cos(i*2*np.pi/num_gon+phi)*v1[1] + np.sin(i*2*np.pi/num_gon+phi)*v2[1])
        z = center[2] + r* (np.cos(i*2*np.pi/num_gon+phi)*v1[2] + np.sin(i*2*np.pi/num_gon+phi)*v2[2])
        points.append([x,y,z])

    points = np.array(points)
    return points



def calc_deviation(params, anchor_point, sphere_points, direction):
    # 被优化的参数中包含圆心坐标、半径和角度phi
    # input variables: circle_center, r, phi
    # parameters: center_point, first_shell_arm_points

    #circle_center, r, phi = params
    # 从一维数组中提取参数
    assert len(params) >= 5
    circle_center = params[0:3]  # 前三个元素是圆心坐标
    r = params[3]               # 第四个元素是半径
    phi = params[4]             # 第五个元素是角度    

    #print('params:', params)

    norm = circle_center - anchor_point
    norm = norm / np.linalg.norm(norm)

    norm = -norm
    norm = norm * direction


    num_arm = len(sphere_points)
    # calculate polygon points
    polygon_points = get_polygon_points(norm, circle_center, r, num_arm, phi)


    #print('sphere_points:', sphere_points)
    #print('polygon_points:', polygon_points)

    # if direction == -1:
    #     polygon_points = polygon_points[::-1]
    
    # calculate deviation
    deviation = 0.0
    for i in range(num_arm):
        #deviation += (np.linalg.norm(polygon_points[i] - first_shell_arm_points[i]))
        #deviation += np.square(np.linalg.norm(polygon_points[i] - first_shell_arm_points[i]))
        dist = (polygon_points[i][0]-sphere_points[i][0])**2
        dist = dist + (polygon_points[i][1]-sphere_points[i][1])**2
        dist = dist + (polygon_points[i][2]-sphere_points[i][2])**2
        dist = dist**0.5
        deviation = deviation + dist**2
    
    #print('deviation:', deviation)
    return deviation

def get_optimized_points(circle_center, r, phi, anchor_point, num_arm, direction):
    # 从输入参数中计算优化后的多边形的顶点 

    norm = circle_center - anchor_point
    norm = norm / np.linalg.norm(norm)

    norm = -norm
    norm = norm * direction

    optimized_points = get_polygon_points(norm, circle_center, r, num_arm, phi)
    return optimized_points

def determine_rotation_direction(points, center_point, normal):
    """
    判断点集相对于中心点和法向量的旋转方向
    
    参数:
    points: np.array, 形状为(n, 3)的点集
    center_point: np.array, 形状为(3,)的中心点
    normal: np.array, 形状为(3,)的法向量
    
    返回:
    1 表示顺时针, -1 表示逆时针
    """
    # 确保normal是单位向量
    normal = normal / np.linalg.norm(normal)
    
    # 计算第一个基向量 (与normal垂直)
    v1 = np.array([-normal[1], normal[0], 0])
    v1 = v1 / np.linalg.norm(v1)
    
    # 计算第二个基向量
    v2 = np.cross(normal, v1)
    
    # 将点投影到由v1和v2定义的平面上
    projected_points = []
    for point in points:
        # 将点相对于中心点的向量投影到v1-v2平面
        relative_vector = point - center_point
        x = np.dot(relative_vector, v1)
        y = np.dot(relative_vector, v2)
        projected_points.append([x, y])
    
    # 计算相邻点之间的叉积和
    total_cross = 0
    projected_points = np.array(projected_points)
    n = len(projected_points)
    
    for i in range(n):
        p1 = projected_points[i]
        p2 = projected_points[(i + 1) % n]
        cross_product = np.cross(p1, p2)
        total_cross += cross_product
    
    # 如果叉积和为正，说明是逆时针方向；为负说明是顺时针方向
    return -1 if total_cross > 0 else 1




def R(theta, u):
    """Optimized rotation matrix calculation using precomputed terms.
    Args:
        theta (float): Rotation angle in radians
        u (array-like): Unit vector [ux, uy, uz] representing rotation axis (passing 0,0,0)
        
    Returns:
        numpy.ndarray: 3x3 rotation matrix for rotating around axis u by angle theta
    """
    ct = cos(theta)
    st = sin(theta)
    omct = 1.0 - ct
    ux, uy, uz = u
    
    ux_uy = ux * uy
    ux_uz = ux * uz
    uy_uz = uy * uz
    
    return np.array([
        [ct + ux*ux * omct,      ux_uy * omct - uz*st,  ux_uz * omct + uy*st],
        [ux_uy * omct + uz*st,   ct + uy*uy * omct,     uy_uz * omct - ux*st],
        [ux_uz * omct - uy*st,   uy_uz * omct + ux*st,  ct + uz*uz * omct]
    ])

def Rotate3(anchor, pointToRotate, onePointOnAxis, theta):

    # anchor: anchor point (1x3)
    # onePointOnAxis: one point on the rotation axis which passes through the anchor point (1x3)
    
    # pointToRotate: the point to rotate (1x3)
    # theta: rotation angle (rad)


    # if 'onePointOnAxis', 'anchor' are not numpy array, make them np.array first
    if not isinstance(anchor, np.ndarray):
        anchor = np.array(anchor)
    if not isinstance(onePointOnAxis, np.ndarray):
        onePointOnAxis = np.array(onePointOnAxis)
    if not isinstance(pointToRotate, np.ndarray):
        pointToRotate = np.array(pointToRotate)

    u = onePointOnAxis - anchor
    u = u / np.linalg.norm(u)         

    r = R(theta, u)

    # rotated = []
    # for i in range(3):
    #     rotated.append((sum([r[j][i] * (pointToRotate[j]-anchor[j]) for j in range(3)])))
    # for i in range(3):
    #     rotated[i] = rotated[i] + anchor[i]

    relative_pos = pointToRotate - anchor
    rotated = r @ relative_pos + anchor

    return rotated


# Find connected components containing arm atoms using BFS
def find_connected_atoms(adj_matrix, start_atoms):
    visited = set()
    queue = list(start_atoms)
    visited.update(start_atoms)
    
    while queue:
        current = queue.pop(0)
        for neighbor in range(len(adj_matrix)):
            if adj_matrix[current, neighbor] == 1 and neighbor not in visited:
                queue.append(neighbor)
                visited.add(neighbor)
    
    return sorted(list(visited))


def mol2adjmat(input_sdf):
    mol = Chem.SDMolSupplier(input_sdf, removeHs=False)[0]
    natoms = mol.GetNumAtoms()
    adj_matrix = np.zeros((natoms, natoms))

    # Fill adjacency matrix
    for bond in mol.GetBonds():
        i = bond.GetBeginAtomIdx()
        j = bond.GetEndAtomIdx() 
        adj_matrix[i,j] = 1
        adj_matrix[j,i] = 1
    
    return adj_matrix


def get_connected_fragment(adj_mat, input_atom_indices, index_start_from_1=True):
    """
    Find connected atoms in a fragment after breaking bonds between anchor and arm atoms
    
    Args:
        adj_mat: adjacency matrix of the molecule
        input_atom_indices: list containing [anchor_atom, [arm_atoms]]
        index_start_from_1: whether input indices start from 1 (True) or 0 (False)
    
    Returns:
        list of atom indices in the connected fragment
    """
    # Convert input indices to 0-based indexing if needed
    if index_start_from_1:
        anchor_idx = input_atom_indices[0] - 1
        arm_indices = [x-1 for x in input_atom_indices[1]]
    else:
        anchor_idx = input_atom_indices[0]
        arm_indices = input_atom_indices[1]

    # Make a copy of adjacency matrix to avoid modifying the original
    adj_matrix = adj_mat.copy()
    
    # Break bonds between anchor and arms
    for arm_idx in arm_indices:
        adj_matrix[anchor_idx, arm_idx] = 0
        adj_matrix[arm_idx, anchor_idx] = 0

    # Get connected atoms 
    connected_atoms = find_connected_atoms(adj_matrix, arm_indices)

    if index_start_from_1:
        result_indices = [x+1 for x in connected_atoms]
    else:
        result_indices = connected_atoms
        
    return result_indices



def get_anchor_and_arm_coordinates_from_xyz(input_xyz, input_atom_indices, index_start_from_1=True):
    """
    Get XYZ coordinates of anchor atom and arm atoms from an XYZ file.
    
    Args:
        input_xyz: path to XYZ file
        input_atom_indices: list containing [anchor_atom, [arm_atoms]]
        index_start_from_1: whether input indices start from 1 (True) or 0 (False)
    
    Returns:
        tuple: (anchor_coords, arm_coords) where anchor_coords is a list [x,y,z] 
        and arm_coords is a list of [x,y,z] coordinates
    """
    # Read XYZ file
    with open(input_xyz, 'r') as f:
        lines = f.readlines()
    
    # Parse XYZ format: first line is number of atoms, second line is comment, then coordinates
    num_atoms = int(lines[0].strip())
    coordinate_lines = lines[2:2+num_atoms]  # Skip first two lines
    
    # Parse coordinates
    coords = []
    for line in coordinate_lines:
        parts = line.strip().split()
        if len(parts) >= 4:  # element symbol + x, y, z coordinates
            x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
            coords.append([x, y, z])
    
    if len(coords) != num_atoms:
        raise ValueError(f"Expected {num_atoms} atoms but found {len(coords)} coordinate lines in {input_xyz}")
    
    # Get anchor atom coordinates
    if index_start_from_1:
        anchor_idx = input_atom_indices[0] - 1
        arm_indices = [x-1 for x in input_atom_indices[1]]
    else:
        anchor_idx = input_atom_indices[0]
        arm_indices = input_atom_indices[1]
    
    # Validate indices
    if anchor_idx >= num_atoms or anchor_idx < 0:
        raise ValueError(f"Anchor atom index {anchor_idx + (1 if index_start_from_1 else 0)} is out of range (1-{num_atoms})")
    
    for i, arm_idx in enumerate(arm_indices):
        if arm_idx >= num_atoms or arm_idx < 0:
            raise ValueError(f"Arm atom index {arm_idx + (1 if index_start_from_1 else 0)} is out of range (1-{num_atoms})")
    
    anchor_coords = coords[anchor_idx]
    
    # Get arm atoms coordinates
    arm_coords = []
    for idx in arm_indices:
        arm_coords.append(coords[idx])
    
    return anchor_coords, arm_coords


def read_xyz_coordinates(input_xyz):
    """
    Read all coordinates from an XYZ file.
    
    Args:
        input_xyz: path to XYZ file
    
    Returns:
        tuple: (element_symbols, coordinates) where coordinates is a numpy array of shape (n_atoms, 3)
    """
    with open(input_xyz, 'r') as f:
        lines = f.readlines()
    
    # Parse XYZ format
    num_atoms = int(lines[0].strip())
    coordinate_lines = lines[2:2+num_atoms]  # Skip first two lines
    
    # Parse coordinates and element symbols
    element_symbols = []
    coords = []
    for line in coordinate_lines:
        parts = line.strip().split()
        if len(parts) >= 4:  # element symbol + x, y, z coordinates
            element_symbols.append(parts[0])
            x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
            coords.append([x, y, z])
    
    if len(coords) != num_atoms:
        raise ValueError(f"Expected {num_atoms} atoms but found {len(coords)} coordinate lines")
    
    return element_symbols, np.array(coords)


def get_anchor_and_arm_coordinates(input_sdf, input_atom_indices, index_start_from_1=True):
    """
    Get XYZ coordinates of anchor atom and arm atoms from an SDF file.
    
    Args:
        input_sdf: path to SDF file
        input_atom_indices: list containing [anchor_atom, [arm_atoms]]
        index_start_from_1: whether input indices start from 1 (True) or 0 (False)
    
    Returns:
        tuple: (anchor_coords, arm_coords) where anchor_coords is a list [x,y,z] 
        and arm_coords is a list of [x,y,z] coordinates
    """
    mol = Chem.SDMolSupplier(input_sdf, removeHs=False)[0]
    conf = mol.GetConformer()

    # Get anchor atom coordinates
    if index_start_from_1:
        anchor_idx = input_atom_indices[0] - 1
        arm_indices = [x-1 for x in input_atom_indices[1]]
    else:
        anchor_idx = input_atom_indices[0]
        arm_indices = input_atom_indices[1]

    anchor_pos = conf.GetAtomPosition(anchor_idx)
    anchor_coords = [anchor_pos.x, anchor_pos.y, anchor_pos.z]

    # Get arm atoms coordinates
    arm_coords = []
    for idx in arm_indices:
        pos = conf.GetAtomPosition(idx)
        arm_coords.append([pos.x, pos.y, pos.z])

    return anchor_coords, arm_coords

