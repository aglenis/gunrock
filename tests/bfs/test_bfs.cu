// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * test_bfs.cu
 *
 * @brief Simple test driver program for breadth-first search.
 */

#include <stdio.h> 
#include <string>
#include <deque>
#include <vector>
#include <iostream>

// Utilities and correctness-checking
#include <gunrock/util/test_utils.cuh>

// Graph construction utils
#include <gunrock/graphio/market.cuh>

// BFS includes
#include <gunrock/app/bfs/bfs_enactor.cuh>
#include <gunrock/app/bfs/bfs_problem.cuh>
#include <gunrock/app/bfs/bfs_functor.cuh>

// Operator includes
#include <gunrock/oprtr/advance/kernel.cuh>
#include <gunrock/oprtr/filter/kernel.cuh>

#include <moderngpu.cuh>

using namespace gunrock;
using namespace gunrock::util;
using namespace gunrock::oprtr;
using namespace gunrock::app::bfs;


/******************************************************************************
 * Defines, constants, globals 
 ******************************************************************************/

bool g_verbose;
bool g_undirected;
bool g_quick;
bool g_stream_from_host;

/******************************************************************************
 * Housekeeping Routines
 ******************************************************************************/
 void Usage()
 {
 printf("\ntest_bfs <graph type> <graph type args> [--device=<device_index>] "
        "[--undirected] [--instrumented] [--src=<source index>] [--quick] "
        "[--mark-pred] [--queue-sizing=<scale factor>]\n"
        "[--v] [--iteration-num=<iteration numbers>] [--traversal-mode=<mode>]\n"
        "\n"
        "Graph types and args:\n"
        "  market [<file>]\n"
        "    Reads a Matrix-Market coordinate-formatted graph of directed/undirected\n"
        "    edges from stdin (or from the optionally-specified file).\n"
        
        "  --device=<device_index>  Set GPU device for running the graph primitive.\n"
        "  --undirected If set then treat the graph as undirected.\n"
        "  --instrumented If set then kernels keep track of queue-search_depth\n"
        "  and barrier duty (a relative indicator of load imbalance.)\n"
        "  --src Begins BFS from the vertex <source index>. If set as randomize\n"
        "  then will begin with a random source vertex.\n"
        "  If set as largestdegree then will begin with the node which has\n"
        "  largest degree.\n"
        "  --quick If set will skip the CPU validation code.\n"
        "  --mark-pred If set then keep not only label info but also predecessor info.\n"
        "  --queue-sizing Allocates a frontier queue sized at (graph-edges * <scale factor>).\n"
        "  Default is 1.0\n"
        " --iteration-num sets how many times you want t operform the algorithm on the dataset. Default is 1.\n"
        " --traversal-mode sets the traversal strategy, default is 0 (load-balanced), 1 for dynamic cooperative method.\n"
        );
 }

 /**
  * @brief Displays the BFS result (i.e., distance from source)
  *
  * @param[in] source_path Search depth from the source for each node.
  * @param[in] preds Predecessor node id for each node.
  * @param[in] nodes Number of nodes in the graph.
  * @param[in] MARK_PREDECESSORS Whether to show predecessor of each node.
  * @param[in] ENABLE_IDEMPOTENCE Whether to enable idempotence mode.
  */
 template<typename VertexId, typename SizeT>
 void DisplaySolution(VertexId *source_path, VertexId *preds, SizeT nodes, bool MARK_PREDECESSORS, bool ENABLE_IDEMPOTENCE)
 {
    if (nodes > 40)
        nodes = 40;
    printf("[");
    for (VertexId i = 0; i < nodes; ++i) {
        PrintValue(i);
        printf(":");
        PrintValue(source_path[i]);
        if (MARK_PREDECESSORS && !ENABLE_IDEMPOTENCE) {
            printf(",");
            PrintValue(preds[i]);
        }
        printf(" ");
    }
    printf("]\n");
 }

 /**
  * Performance/Evaluation statistics
  */ 

struct Stats {
    const char *name;
    Statistic rate;
    Statistic search_depth;
    Statistic redundant_work;
    Statistic duty;

    Stats() : name(NULL), rate(), search_depth(), redundant_work(), duty() {}
    Stats(const char *name) : name(name), rate(), search_depth(), redundant_work(), duty() {}
};

/**
 * @brief Displays timing and correctness statistics
 *
 * @tparam MARK_PREDECESSORS
 * @tparam VertexId
 * @tparam Value
 * @tparam SizeT
 * 
 * @param[in] stats Reference to the Stats object defined in RunTests
 * @param[in] src Source node where BFS starts
 * @param[in] h_labels Host-side vector stores computed labels for validation
 * @param[in] graph Reference to the CSR graph we process on
 * @param[in] elapsed Total elapsed kernel running time
 * @param[in] search_depth Maximum search depth of the BFS algorithm
 * @param[in] total_queued Total element queued in BFS kernel running process
 * @param[in] avg_duty Average duty of the BFS kernels
 */
template<
    bool MARK_PREDECESSORS,
    typename VertexId,
    typename Value,
    typename SizeT>
void DisplayStats(
    Stats               &stats,
    VertexId            src,
    VertexId            *h_labels,
    const Csr<VertexId, Value, SizeT> &graph,
    double              elapsed,
    VertexId            search_depth,
    long long           total_queued,
    double              avg_duty)
{
    // Compute nodes and edges visited
    SizeT edges_visited = 0;
    SizeT nodes_visited = 0;
    for (VertexId i = 0; i < graph.nodes; ++i) {
        if (h_labels[i] > -1) {
            ++nodes_visited;
            edges_visited += graph.row_offsets[i+1] - graph.row_offsets[i];
        }
    }

    double redundant_work = 0.0;
    if (total_queued > 0) {
        redundant_work = ((double) total_queued - edges_visited) / edges_visited;        // measure duplicate edges put through queue
    }
    redundant_work *= 100;

    // Display test name
    printf("[%s] finished. ", stats.name);

    // Display statistics
    if (nodes_visited < 5) {
        printf("Fewer than 5 vertices visited.\n");
    } else {
        // Display the specific sample statistics
        double m_teps = (double) edges_visited / (elapsed * 1000.0);
        printf(" elapsed: %.3f ms, rate: %.3f MiEdges/s", elapsed, m_teps);
        if (search_depth != 0) printf(", search_depth: %lld", (long long) search_depth);
        if (avg_duty != 0) {
            printf("\n avg CTA duty: %.2f%%", avg_duty * 100);
        }
        printf("\n src: %lld, nodes_visited: %lld, edges visited: %lld",
            (long long) src, (long long) nodes_visited, (long long) edges_visited);
        if (total_queued > 0) {
            printf(", total queued: %lld", total_queued);
        }
        if (redundant_work > 0) {
            printf(", redundant work: %.2f%%", redundant_work);
        }
        printf("\n");
    }
    
}




/******************************************************************************
 * BFS Testing Routines
 *****************************************************************************/

 /**
  * @brief A simple CPU-based reference BFS ranking implementation.
  *
  * @tparam VertexId
  * @tparam Value
  * @tparam SizeT
  *
  * @param[in] graph Reference to the CSR graph we process on
  * @param[in] source_path Host-side vector to store CPU computed labels for each node
  * @param[in] predecessor Host-side vector to store CPU computed predecessor for each node
  * @param[in] src Source node where BFS starts
  */
 template<
    typename VertexId,
    typename Value,
    typename SizeT,
    bool MARK_PREDECESSORS>
void SimpleReferenceBfs(
    const Csr<VertexId, Value, SizeT>       &graph,
    VertexId                                *source_path,
    VertexId                                *predecessor,
    VertexId                                src)
{
    //initialize distances
    for (VertexId i = 0; i < graph.nodes; ++i) {
        source_path[i] = -1;
        if (MARK_PREDECESSORS)
            predecessor[i] = -1;
    }
    source_path[src] = 0;
    VertexId search_depth = 0;

    // Initialize queue for managing previously-discovered nodes
    std::deque<VertexId> frontier;
    frontier.push_back(src);

    //
    //Perform BFS
    //

    CpuTimer cpu_timer;
    cpu_timer.Start();
    while (!frontier.empty()) {
        
        // Dequeue node from frontier
        VertexId dequeued_node = frontier.front();
        frontier.pop_front();
        VertexId neighbor_dist = source_path[dequeued_node] + 1;

        // Locate adjacency list
        int edges_begin = graph.row_offsets[dequeued_node];
        int edges_end = graph.row_offsets[dequeued_node + 1];

        for (int edge = edges_begin; edge < edges_end; ++edge) {
            //Lookup neighbor and enqueue if undiscovered
            VertexId neighbor = graph.column_indices[edge];
            if (source_path[neighbor] == -1) {
                source_path[neighbor] = neighbor_dist;
                if (MARK_PREDECESSORS)
                    predecessor[neighbor] = dequeued_node;
                if (search_depth < neighbor_dist) {
                    search_depth = neighbor_dist;
                }
                frontier.push_back(neighbor);
            }
        }
    }

    if (MARK_PREDECESSORS)
        predecessor[src] = -1;

    cpu_timer.Stop();
    float elapsed = cpu_timer.ElapsedMillis();
    search_depth++;

    printf("CPU BFS finished in %lf msec. Search depth is:%d\n", elapsed, search_depth);
}

/**
 * @brief Run BFS tests
 *
 * @tparam VertexId
 * @tparam Value
 * @tparam SizeT
 * @tparam INSTRUMENT
 * @tparam MARK_PREDECESSORS
 *
 * @param[in] graph Reference to the CSR graph we process on
 * @param[in] src Source node where BFS starts
 * @param[in] max_grid_size Maximum CTA occupancy
 * @param[in] num_gpus Number of GPUs
 * @param[in] max_queue_sizing Scaling factor used in edge mapping
 * @param[in] iterations Number of iterations for running the test
 * @param[in] traversal_mode Graph traversal mode: Load-balanced or Dynamic cooperative
 * @param[in] context CudaContext pointer for moderngpu APIs
 *
 */
template <
    typename VertexId,
    typename Value,
    typename SizeT,
    bool INSTRUMENT,
    bool MARK_PREDECESSORS,
    bool ENABLE_IDEMPOTENCE>
void RunTests(
    const Csr<VertexId, Value, SizeT> &graph,
    VertexId src,
    int max_grid_size,
    int num_gpus,
    double max_queue_sizing,
    int iterations,
    int traversal_mode,
    CudaContext& context)
{
        typedef BFSProblem<
            VertexId,
            SizeT,
            Value,
            MARK_PREDECESSORS,
            ENABLE_IDEMPOTENCE,
            (MARK_PREDECESSORS && ENABLE_IDEMPOTENCE)> Problem; // does not use double buffer

        // Allocate host-side label array (for both reference and gpu-computed results)
        VertexId    *reference_labels       = (VertexId*)malloc(sizeof(VertexId) * graph.nodes);
        VertexId    *reference_preds        = (VertexId*)malloc(sizeof(VertexId) * graph.nodes);
        VertexId    *h_labels               = (VertexId*)malloc(sizeof(VertexId) * graph.nodes);
        VertexId    *reference_check_label  = (g_quick) ? NULL : reference_labels;
        VertexId    *reference_check_preds  = NULL;
        VertexId    *h_preds                = NULL;
        if (MARK_PREDECESSORS) {
            h_preds = (VertexId*)malloc(sizeof(VertexId) * graph.nodes);
            if (!g_quick) {
                reference_check_preds = reference_preds;
            }
            
        }


        // Allocate BFS enactor map
        BFSEnactor<INSTRUMENT> bfs_enactor(g_verbose);

        // Allocate problem on GPU
        Problem *csr_problem = new Problem;
        util::GRError(csr_problem->Init(
            g_stream_from_host,
            graph,
            num_gpus), "Problem BFS Initialization Failed", __FILE__, __LINE__);

        //
        // Compute reference CPU BFS solution for source-distance
        //
        if (reference_check_label != NULL)
        {
            printf("compute ref value\n");
            SimpleReferenceBfs<VertexId, Value, SizeT, MARK_PREDECESSORS>(
                    graph,
                    reference_check_label,
                    reference_check_preds,
                    src);
            printf("\n");
        }

        Stats *stats = new Stats("GPU BFS");

        long long           total_queued = 0;
        VertexId            search_depth = 0;
        double              avg_duty = 0.0;

        // Perform BFS
        GpuTimer gpu_timer;

        float elapsed = 0.0f;

        for (int iter = 0; iter < iterations; ++iter)
        {
            util::GRError(csr_problem->Reset(src, bfs_enactor.GetFrontierType(), max_queue_sizing), "BFS Problem Data Reset Failed", __FILE__, __LINE__);
            gpu_timer.Start();
            util::GRError(bfs_enactor.template Enact<Problem>(context, csr_problem, src, max_grid_size, traversal_mode), "BFS Problem Enact Failed", __FILE__, __LINE__);
            gpu_timer.Stop();

            elapsed += gpu_timer.ElapsedMillis();
        }
    
        elapsed /= iterations;

        bfs_enactor.GetStatistics(total_queued, search_depth, avg_duty);


        // Copy out results
        util::GRError(csr_problem->Extract(h_labels, h_preds), "BFS Problem Data Extraction Failed", __FILE__, __LINE__);

        // Verify the result
        if (reference_check_label != NULL) {
            if (!ENABLE_IDEMPOTENCE) {
                printf("Label Validity: ");
                int error_num = CompareResults(h_labels, reference_check_label, graph.nodes, true);
                if (error_num > 0)
                printf("%d errors occurred.\n", error_num);
            } else {
                if (!MARK_PREDECESSORS) {
                    printf("Label Validity: ");
                    int error_num = CompareResults(h_labels, reference_check_label, graph.nodes, true);
                    if (error_num > 0)
                        printf("%d errors occurred.\n", error_num);
                }
            }
        }
        printf("\nFirst 40 labels of the GPU result."); 
        // Display Solution
        DisplaySolution(h_labels, h_preds, graph.nodes, MARK_PREDECESSORS, ENABLE_IDEMPOTENCE);

        DisplayStats<MARK_PREDECESSORS>(
            *stats,
            src,
            h_labels,
            graph,
            elapsed,
            search_depth,
            total_queued,
            avg_duty);


        // Cleanup
        delete stats;
        if (csr_problem) delete csr_problem;
        if (reference_labels) free(reference_labels);
        if (h_labels) free(h_labels);
        if (h_preds) free(h_preds);

        cudaDeviceSynchronize();
}

/**
 * @brief RunTests entry
 *
 * @tparam VertexId
 * @tparam Value
 * @tparam SizeT
 *
 * @param[in] graph Reference to the CSR graph we process on
 * @param[in] args Reference to the command line arguments
 * @param[in] context CudaContext pointer for moderngpu APIs
 */
template <
    typename VertexId,
    typename Value,
    typename SizeT>
void RunTests(
    Csr<VertexId, Value, SizeT> &graph,
    CommandLineArgs &args,
    CudaContext& context)
{
    VertexId            src                 = -1;           // Use whatever the specified graph-type's default is
    std::string         src_str;
    bool                instrumented        = false;        // Whether or not to collect instrumentation from kernels
    bool                mark_pred           = false;        // Whether or not to mark src-distance vs. parent vertices
    bool                idempotence         = false;        // Whether or not to enable idempotence operation
    int                 max_grid_size       = 0;            // maximum grid size (0: leave it up to the enactor)
    int                 num_gpus            = 1;            // Number of GPUs for multi-gpu enactor to use
    double              max_queue_sizing    = 1.0;          // Maximum size scaling factor for work queues (e.g., 1.0 creates n and m-element vertex and edge frontiers).
    int                 iterations          = 1;
    int                 traversal_mode      = 0;

    instrumented = args.CheckCmdLineFlag("instrumented");
    args.GetCmdLineArgument("src", src_str);
    if (src_str.empty()) {
        src = 0;
    } else if (src_str.compare("randomize") == 0) {
        src = graphio::RandomNode(graph.nodes);
    } else if (src_str.compare("largestdegree") == 0) {
        int temp;
        src = graph.GetNodeWithHighestDegree(temp);
    } else {
        args.GetCmdLineArgument("src", src);
    }

    args.GetCmdLineArgument("iteration-num", iterations);

    args.GetCmdLineArgument("grid-size", max_grid_size);

    args.GetCmdLineArgument("traversal-mode", traversal_mode);

    //printf("Display neighbor list of src:\n");
    //graph.DisplayNeighborList(src);

    g_quick = args.CheckCmdLineFlag("quick");
    mark_pred = args.CheckCmdLineFlag("mark-pred");
    idempotence = args.CheckCmdLineFlag("idempotence");
    args.GetCmdLineArgument("queue-sizing", max_queue_sizing);
    g_verbose = args.CheckCmdLineFlag("v");

    if (instrumented) {
        if (mark_pred) {
            if (idempotence) {
                RunTests<VertexId, Value, SizeT, true, true, true>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            } else {
                RunTests<VertexId, Value, SizeT, true, true, false>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            }
        } else {
            if (idempotence) {
                RunTests<VertexId, Value, SizeT, true, false, true>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            } else {
                RunTests<VertexId, Value, SizeT, true, false, false>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            }
        }
    } else {
        if (mark_pred) {
            if (idempotence) {
                RunTests<VertexId, Value, SizeT, false, true, true>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            } else {
                RunTests<VertexId, Value, SizeT, false, true, false>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            }
        } else {
            if (idempotence) {
                RunTests<VertexId, Value, SizeT, false, false, true>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            } else {
                RunTests<VertexId, Value, SizeT, false, false, false>(
                        graph,
                        src,
                        max_grid_size,
                        num_gpus,
                        max_queue_sizing,
                        iterations,
                        traversal_mode,
                        context);
            }
        }
    }

}



/******************************************************************************
* Main
******************************************************************************/

int main( int argc, char** argv)
{
	CommandLineArgs args(argc, argv);

	if ((argc < 2) || (args.CheckCmdLineFlag("help"))) {
		Usage();
		return 1;
	}

	//DeviceInit(args);
	//cudaSetDeviceFlags(cudaDeviceMapHost);

    int dev = 0;
    args.GetCmdLineArgument("device", dev);
    ContextPtr context = mgpu::CreateCudaDevice(dev);

	//srand(0);									// Presently deterministic
	//srand(time(NULL));

	// Parse graph-contruction params
	g_undirected = args.CheckCmdLineFlag("undirected");

	std::string graph_type = argv[1];
	int flags = args.ParsedArgc();
	int graph_args = argc - flags - 1;

	if (graph_args < 1) {
		Usage();
		return 1;
	}
	
	//
	// Construct graph and perform search(es)
	//

	if (graph_type == "market") {

		// Matrix-market coordinate-formatted graph file

		typedef int VertexId;							// Use as the node identifier type
		typedef int Value;								// Use as the value type
		typedef int SizeT;								// Use as the graph size type
		Csr<VertexId, Value, SizeT> csr(false);         // default value for stream_from_host is false

		if (graph_args < 1) { Usage(); return 1; }
		char *market_filename = (graph_args == 2) ? argv[2] : NULL;
		if (graphio::BuildMarketGraph<false>(
			market_filename, 
			csr, 
			g_undirected,
			false) != 0) // no inverse graph
		{
			return 1;
		}

		csr.PrintHistogram();

		// Run tests
		RunTests(csr, args, *context);

    } else {

		// Unknown graph type
		fprintf(stderr, "Unspecified graph type\n");
		return 1;

	}
	return 0;
}
