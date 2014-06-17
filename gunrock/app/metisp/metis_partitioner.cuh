// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * rp_partitioner.cuh
 *
 * @brief Implementation of random partitioner
 */

#pragma once

#include <metis.h>

#include <gunrock/app/partitioner_base.cuh>
#include <gunrock/util/memset_kernel.cuh>
#include <gunrock/util/multithread_utils.cuh>

namespace gunrock {
namespace app {
namespace metisp {

template <
    typename VertexId,
    typename SizeT,
    typename Value>
struct MetisPartitioner : PartitionerBase<VertexId,SizeT,Value>
{
    typedef Csr<VertexId,Value,SizeT> GraphT;

    // Members
    float *weitage;

    // Methods
    MetisPartitioner()
    {
        weitage=NULL;
    }

    MetisPartitioner(const GraphT &graph,
                      int   num_gpus,
                      float *weitage = NULL)
    {
        Init2(graph,num_gpus,weitage);
    }

    void Init2(
        const GraphT &graph,
        int num_gpus,
        float *weitage)
    {
        this->Init(graph,num_gpus);
        this->weitage=new float[num_gpus+1];
        if (weitage==NULL)
            for (int gpu=0;gpu<num_gpus;gpu++) this->weitage[gpu]=1.0f/num_gpus;
        else {
            float sum=0;
            for (int gpu=0;gpu<num_gpus;gpu++) sum+=weitage[gpu];
            for (int gpu=0;gpu<num_gpus;gpu++) this->weitage[gpu]=weitage[gpu]/sum; 
        }
        for (int gpu=0;gpu<num_gpus;gpu++) this->weitage[gpu+1]+=this->weitage[gpu];
    }

    ~MetisPartitioner()
    {
        if (weitage!=NULL)
        {
            delete[] weitage;weitage=NULL;
        }
    }

    cudaError_t Partition(
        GraphT*    &sub_graphs,
        int**      &partition_tables,
        VertexId** &convertion_tables,
        VertexId** &original_vertexes,
        SizeT**    &in_offsets,
        SizeT**    &out_offsets)
    {
        cudaError_t retval = cudaSuccess;
        idx_t       nodes  = this->graph->nodes;
        idx_t       ngpus  = this->num_gpus;
        idx_t       ncons  = 1;
        idx_t       objval;
        idx_t*      tpartition_table = new idx_t[nodes];//=this->partition_tables[0];

        int Status = METIS_PartGraphKway(
                    &nodes,                      // nvtxs  : the number of vertices in the graph
                    &ncons,                      // ncon   : the number of balancing constraints
                    this->graph->row_offsets,    // xadj   : the adjacency structure of the graph
                    this->graph->column_indices, // adjncy : the adjacency structure of the graph
                    NULL,                        // vwgt   : the weights of the vertices
                    NULL,                        // vsize  : the size of the vertices
                    NULL,                        // adjwgt : the weights of the edges
                    &ngpus,                      // nparts : the number of parts to partition the graph
                    NULL,                        // tpwgts : the desired weight for each partition and constraint
                    NULL,                        // ubvec  : the allowed load imbalance tolerance 4 each constraint
                    NULL,                        // options: the options
                    &objval,                     // objval : the returned edge-cut or the total communication volume
                    tpartition_table);           // part   : the returned partition vector of the graph
        
        for (SizeT i=0;i<nodes;i++) this->partition_tables[0][i]=tpartition_table[i];
        delete[] tpartition_table;tpartition_table=NULL;

        retval = this->MakeSubGraph();
        sub_graphs        = this->sub_graphs;
        partition_tables  = this->partition_tables;
        convertion_tables = this->convertion_tables;
        original_vertexes = this->original_vertexes;
        in_offsets        = this->in_offsets;
        out_offsets       = this->out_offsets;
        return retval;
    }
};

} //namespace metisp
} //namespace app
} //namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
