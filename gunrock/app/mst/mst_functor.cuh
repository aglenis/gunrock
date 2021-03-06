// -----------------------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// -----------------------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// -----------------------------------------------------------------------------

/**
 * @file
 * mst_functor.cuh
 *
 * @brief Device functions for Minimum Spanning Tree problem.
 */

#pragma once

#include <gunrock/app/problem_base.cuh>
#include <gunrock/app/mst/mst_problem.cuh>

namespace gunrock {
namespace app {
namespace mst {

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * find the successor of each vertex and add to MST outputs
 *
 * @tparam VertexId    Type of signed integer use as vertex id
 * @tparam SizeT       Type of unsigned integer for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct SuccFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Forward Edge Mapping condition function.
   * Used for generating successor array
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   *
   * \return Whether to load the apply function for the edge and include
   * the destination node in the next frontier.
   */
  static __device__ __forceinline__ bool CondEdge(
    VertexId s_id, VertexId d_id, DataSlice *problem,
    VertexId e_id = 0, VertexId e_id_in = 0)
  {
    return true;
  }

  /**
   * @brief Forward Edge Mapping apply function.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   */
  static __device__ __forceinline__ void ApplyEdge(
    VertexId s_id,  VertexId d_id, DataSlice *problem,
    VertexId e_id = 0, VertexId e_id_in = 0)
  {
    /*
    if (problem->d_reduced_vals[s_id] == problem->d_edge_weights[e_id])
      printf("s_id: %d, d_id: %d, e_id: %d, origin_e_id: %d, "
        "reduced_weight: %d, edge_weight: %d, successors[s_id]: %d \n",
         s_id, d_id, e_id, problem->d_origin_edges[e_id],
         problem->d_reduced_vals[s_id],
         problem->d_edge_weights[e_id],
         problem->d_successors[s_id]);
    */

    // find successors that contribute to the reduced weight value
    if (problem->d_reduced_vals[s_id] == problem->d_edge_weights[e_id])
    {
      // select one successor with minimum vertex id
      if (atomicMin(&problem->d_successors[s_id], d_id) > d_id) // update min
      {
        // select one MST edge connected to the successor
        util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
          problem->d_origin_edges[e_id], problem->d_temp_storage + s_id);
      }
    }
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for removing cycles in successors
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct MarkFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Forward Edge Mapping condition function.
   * Used for finding Vertex Id that have minimum weight value.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   *
   * \return Whether to load the apply function for the edge and include
   * the destination node in the next frontier.
   */
  static __device__ __forceinline__ bool CondEdge(
    VertexId s_id, VertexId d_id, DataSlice *problem,
    VertexId e_id = 0, VertexId e_id_in = 0)
  {
    return true;
  }

  /**
   * @brief Forward Edge Mapping apply function.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   */
  static __device__ __forceinline__ void ApplyEdge(
  VertexId s_id, VertexId d_id, DataSlice *problem,
  VertexId e_id = 0, VertexId e_id_in = 0)
  {
    // mark minimum spanning tree output edges
    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
      1, problem->d_mst_output + problem->d_temp_storage[s_id]);
    // problem->d_mst_output[problem->d_temp_storage[s_id]] = 1;
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for removing cycles in successors
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct CyRmFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Forward Edge Mapping condition function.
   * Used for finding Vertex Id that have minimum weight value.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   *
   * \return Whether to load the apply function for the edge and include
   * the destination node in the next frontier.
   */
  static __device__ __forceinline__ bool CondEdge(
    VertexId s_id, VertexId d_id, DataSlice *problem,
    VertexId e_id = 0, VertexId e_id_in = 0)
  {
    return true;
  }

  /**
   * @brief Forward Edge Mapping apply function.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   */
  static __device__ __forceinline__ void ApplyEdge(
  VertexId s_id, VertexId d_id, DataSlice *problem,
  VertexId e_id = 0, VertexId e_id_in = 0)
  {
    /*
    // mark minimum spanning tree output edges
    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
      1, problem->d_mst_output + problem->d_temp_storage[s_id]);
    // problem->d_mst_output[problem->d_temp_storage[s_id]] = 1;
    __syncthreads(); // make sure finish mark 1 process
    */

    // remove length two cycles
    if (problem->d_successors[s_id] > s_id &&
        problem->d_successors[problem->d_successors[s_id]] == s_id)
    {
      // remove cycles by assigning successor to its s_id
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        s_id, problem->d_successors + s_id);
      // problem->d_successors[s_id] = s_id;

      // remove some edges in the MST output result
      // printf("remove edge: %d\n", problem->d_temp_storage[s_id]);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        0, problem->d_mst_output + problem->d_temp_storage[s_id]);
      // problem->d_mst_output[problem->d_temp_storage[s_id]] = 0;
    }
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions for pointer jumping operation.
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct PJmpFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Vertex mapping condition function. The vertex id is always valid.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v Vertex value
   *
   * \return Whether to load the apply function for the node and include
   * it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    return true;
  }

  /**
   * @brief Vertex mapping apply function. Point the current node to the
   * parent node of its parent node.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v Vertex value
   */
  static __device__ __forceinline__ void ApplyFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    VertexId parent;
    util::io::ModifiedLoad<ProblemData::COLUMN_READ_MODIFIER>::Ld(
      parent, problem->d_successors + node);
    VertexId grand_parent;
    util::io::ModifiedLoad<ProblemData::COLUMN_READ_MODIFIER>::Ld(
      grand_parent, problem->d_successors + parent);
    if (parent != grand_parent)
    {
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        0, problem->d_vertex_flag);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        grand_parent, problem->d_successors + node);
    }
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for remove redundant edges in one super-vertex
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct EgRmFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Forward Edge Mapping condition function.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   *
   * \return Whether to load the apply function for the edge and include
   * the destination node in the next frontier.
   */
  static __device__ __forceinline__ bool CondEdge(
    VertexId s_id, VertexId d_id, DataSlice *problem,
    VertexId e_id = 0, VertexId e_id_in = 0)
  {
    return true;
  }

  /**
   * @brief Forward Edge Mapping apply function.
   * Each edge looks at the super-vertex id of both endpoints
   * and mark -1 (to be removed) if the id is the same
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id Output edge index
   * @param[in] e_id_in Input edge index
   */
  static __device__ __forceinline__ void ApplyEdge(
    VertexId s_id, VertexId d_id, DataSlice *problem,
    VertexId e_id = 0, VertexId e_id_in = 0)
  {
    if (problem->d_successors[s_id] == problem->d_successors[d_id])
    {
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_keys_array + e_id);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_col_indices + e_id);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_edge_weights + e_id);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_origin_edges + e_id);
    }
  }

  /**
   * @brief Vertex mapping condition function.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v Vertex value
   *
   * \return Whether to load the apply function for the node and include
   * it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    return true;
  }

  /**
   * @brief Vertex mapping apply function.
   * removing edges belonging to the same super-vertex
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v Vertex value
   */
  static __device__ __forceinline__ void ApplyFilter(
  VertexId node, DataSlice *problem, Value v = 0)
  {
    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
      problem->d_supervtx_ids[problem->d_keys_array[node]],
      problem->d_keys_array + node);
    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
      problem->d_supervtx_ids[problem->d_col_indices[node]],
      problem->d_col_indices + node);
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for calculating row_offsets array for next iteration
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 *
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct RIdxFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Vertex mapping condition function. Calculate new row_offsets
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v Vertex value
   *
   * \return Whether to load the apply function for the node and include
   * it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    return true;
  }

  /**
   * @brief Vertex mapping apply function.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v Vertex value
   *
   */
  static __device__ __forceinline__ void ApplyFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    if (problem->d_flags_array[node] == 1)
    {
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        node, problem->d_row_offsets + problem->d_keys_array[node]);
    }
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for generate edge flags
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct EIdxFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Vertex mapping condition function. Calculate new row_offsets
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v node value (if any)
   *
   * \return Whether to load the apply function for the node and include
   * it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    return true;
  }

  /**
   * @brief Vertex mapping apply function.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v node value (if any)
   */
  static __device__ __forceinline__ void ApplyFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    if (problem->d_edge_flags[node] == 1)
    {
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        node, problem->d_row_offsets + problem->d_temp_storage[node]);
    }
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for generate edge flags
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct OrFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Vertex mapping condition function.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v node value (if any)
   *
   * \return Whether to load the apply function for the node and include
   * it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    return true;
  }

  /**
   * @brief Vertex mapping apply function.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v node value (if any)
   */
  static __device__ __forceinline__ void ApplyFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
      problem->d_edge_flags[node] | problem->d_flags_array[node],
      problem->d_edge_flags + node);
  }
};

////////////////////////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in MST graph traverse.
 * used for remove duplicated edges between super-vertices
 *
 * @tparam VertexId    Type of signed integer to use as vertex id
 * @tparam SizeT       Type of unsigned integer to use for array indexing
 * @tparam ProblemData Problem data type contains data slice for MST problem
 *
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename ProblemData>
struct SuRmFunctor
{
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Vertex mapping condition function.
   * Mark -1 for unselected edges / weights / keys / eId.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v node value (if any)
   *
   * \return Whether to load the apply function for the node and include
   * it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    return true;
  }

  /**
   * @brief Vertex mapping apply function.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v node value (if any)
   */
  static __device__ __forceinline__ void ApplyFilter(
    VertexId node, DataSlice *problem, Value v = 0)
  {
    if (problem->d_edge_flags[node] == 0)
    {
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_keys_array + node);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_col_indices + node);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_edge_weights + node);
      util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
        -1, problem->d_origin_edges + node);
    }
  }
};

} // mst
} // app
} // gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End: