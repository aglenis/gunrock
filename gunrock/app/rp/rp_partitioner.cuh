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

#include <stdlib.h>
#include <time.h>
#include <algorithm>
#include <vector>

#include <gunrock/app/partitioner_base.cuh>
#include <gunrock/util/memset_kernel.cuh>
#include <gunrock/util/multithread_utils.cuh>

namespace gunrock {
namespace app {
namespace rp {

    template <typename SizeT>
    struct sort_node
    {
    public:
        SizeT posit;
        int   value;
        
        bool operator==(const sort_node& node) const
        {
            return (node.value == value);
        }

        bool operator<(const sort_node& node) const
        {
            return (node.value < value);
        }
        
        sort_node & operator=(const sort_node &rhs)
        {
            this->posit=rhs.posit;
            this->value=rhs.value;
            return *this;
        }
    };

    template <typename SizeT>
    bool compare_sort_node(sort_node<SizeT> A, sort_node<SizeT> B)
    {
        return (A.value<B.value);
    }


template <
    typename VertexId,
    typename SizeT,
    typename Value,
    bool     ENABLE_BACKWARD = false>
struct RandomPartitioner : PartitionerBase<VertexId,SizeT,Value,ENABLE_BACKWARD>
{
    typedef Csr<VertexId,Value,SizeT> GraphT;

    // Members
    float *weitage;

    // Methods
    RandomPartitioner()
    {
        weitage=NULL;
    }

    RandomPartitioner(const GraphT &graph,
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

    ~RandomPartitioner()
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
        SizeT**    &out_offsets,
        SizeT**    &cross_counter,
        SizeT**    &backward_offsets,
        int**      &backward_partitions,
        VertexId** &backward_convertions)
    {
        cudaError_t retval = cudaSuccess;
        int*        tpartition_table=this->partition_tables[0];
        time_t      t = 1406125211; //time(NULL);
        SizeT       nodes  = this->graph->nodes;
        sort_node<SizeT> *sort_list = new sort_node<SizeT>[nodes];

        printf("Partition begin. seed=%ld\n", t);fflush(stdout);

        srand(t);
        for (SizeT node=0;node<nodes;node++)
        {
            sort_list[node].value=rand();
            sort_list[node].posit=node;
        }
        std::vector<sort_node<SizeT> > sort_vector(sort_list, sort_list+nodes);
        std::sort(sort_vector.begin(),sort_vector.end());//,compare_sort_node<SizeT>);
        for (int gpu=0;gpu<this->num_gpus;gpu++)
        for (SizeT pos= gpu==0?0:weitage[gpu-1]*nodes; pos<weitage[gpu]*nodes; pos++)
        {
            tpartition_table[sort_vector[pos].posit]=gpu;
        }

        delete[] sort_list;sort_list=NULL;
        retval = this->MakeSubGraph
                 ();
        sub_graphs          = this->sub_graphs;
        partition_tables    = this->partition_tables;
        convertion_tables   = this->convertion_tables;
        original_vertexes   = this->original_vertexes;
        in_offsets          = this->in_offsets;
        out_offsets         = this->out_offsets;
        cross_counter       = this->cross_counter;
        backward_offsets    = this->backward_offsets;
        backward_partitions = this->backward_partitions;
        backward_convertions= this->backward_convertions;
        return retval;
    }
};

} //namespace rp
} //namespace app
} //namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End: