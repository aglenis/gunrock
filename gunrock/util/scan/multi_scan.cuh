// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * multi_scan.cuh
 *
 * @brief Multi Scan that splict and scan on array
 */

#pragma once

#include <gunrock/util/test_utils.cuh>
//#include <gunrock/util/operators.cuh>

namespace gunrock {
namespace util {
namespace scan {

/*template <
    typename VertexId,              // Type of the select array
    typename SizeT,                 // Type of counters
    //SizeT    NUM_ELEMENTS,          // Number of elements to scan
    //SizeT    NUM_ROWS,              // Number of sub-array to splict into
    SizeT    BLOCK_SIZE = 256,      // Size of element to process by a block
    SizeT    BLOCK_N    = 8,        // log2(BLOCKSIZE)
    bool     EXCLUSIVE  = true>     // Whether or not this is an exclusive scan
struct MultiScan
{*/
    template <
        //typename _VertexId,
        typename _SizeT,
        int      Block_N>
    __device__ __forceinline__ void ScanLoop(
        _SizeT *s_Buffer,
        _SizeT *Sum,
        _SizeT Sum_Offset)
    {
        _SizeT Step=1;
        #pragma unrool
        for (int i=0;i<Block_N;i++)
        {
            _SizeT k = threadIdx.x * Step * 2 + Step -1;
            if (k+Step < blockDim.x*2) s_Buffer[k + Step] += s_Buffer[k];
            Step *= 2;
            __syncthreads();
        } // for i
        if (threadIdx.x == blockDim.x -1)
        {
            if (Sum_Offset !=-1) Sum[Sum_Offset] = s_Buffer[blockDim.x*2-1];
            s_Buffer[blockDim.x*2-1]=0;
        } // if
        __syncthreads();

        Step /= 2;
        #pragma unrool
        for (int i=Block_N-1;i>=0;i--)
        {
            _SizeT k = threadIdx.x * Step * 2 + Step -1;
            if (k+Step < blockDim.x*2)
            {
                _SizeT t = s_Buffer[k];
                s_Buffer[k] = s_Buffer[k+Step];
                s_Buffer[k+Step] += t;
            }
            Step /= 2;
            __syncthreads();
        } // for i
    }

    template <
        typename _VertexId,
        typename _SizeT,
        //_SizeT   Block_Size,
        int      Block_N>
     __global__ void Step0(
        const _SizeT           N,
        const _SizeT           M,
        const _SizeT           N_Next,
        const _VertexId* const Select,
        const int*       const Splict,
              _SizeT*          Buffer,
              _SizeT*          Sum)
    {
        extern __shared__ _SizeT s_Buffer[];
        int Splict0 = -1, Splict1 = -1;
        _SizeT x = (blockIdx.x + blockIdx.y * gridDim.x) * blockDim.x*2 + threadIdx.x;

        if (x - threadIdx.x >= N) return;
        if (x < N) if (Select[x] != 0) 
            Splict0 = Splict[x];
        if (x+blockDim.x < N) if (Select[x+blockDim.x] != 0) 
            Splict1 = Splict[x+blockDim.x];

        for (int y=0;y<M;y++)
        {
            if (y == Splict0) 
                 s_Buffer[threadIdx.x] = 1; 
            else s_Buffer[threadIdx.x] = 0;
            if (y == Splict1) 
                 s_Buffer[threadIdx.x + blockDim.x] = 1; 
            else s_Buffer[threadIdx.x + blockDim.x] = 0;
            __syncthreads();

            if (x/blockDim.x/2 < N_Next) ScanLoop<_SizeT,Block_N>(s_Buffer,Sum,y*N_Next + x/blockDim.x/2);
            else ScanLoop<_SizeT,Block_N>(s_Buffer,Sum,-1);
           
            if (y == Splict0) Buffer[x] = s_Buffer[threadIdx.x];
            if (y == Splict1) Buffer[x + blockDim.x] = s_Buffer[threadIdx.x + blockDim.x];
        } // for y
    } // Step0

    template <
        typename _VertexId,
        typename _SizeT,
        int      Block_N>
    __global__ void Step0b(
        const _SizeT           N,
        const _SizeT           M,
        const _SizeT           N_Next,
        const _VertexId* const Keys,
        const int*       const Splict,
              _SizeT*          Buffer,
              _SizeT*          Sum)
    {
        extern __shared__ _SizeT s_Buffer[];
        int Splict0 = -1, Splict1 = -1;
        _SizeT x = (blockIdx.x + blockIdx.y * gridDim.x) * blockDim.x*2 +threadIdx.x;

        if (x - threadIdx.x >=N) return;
        if (x < N )             Splict0 = Splict[Keys[x]];
        if (x + blockDim.x < N) Splict1 = Splict[Keys[x+blockDim.x]];

        for (int y=0;y<M;y++)
        {
            if (y == Splict0) 
                 s_Buffer[threadIdx.x] = 1; 
            else s_Buffer[threadIdx.x] = 0;
            if (y == Splict1) 
                 s_Buffer[threadIdx.x + blockDim.x] = 1; 
            else s_Buffer[threadIdx.x + blockDim.x] = 0;
            __syncthreads();

            if (x/blockDim.x/2 < N_Next) ScanLoop<_SizeT,Block_N>(s_Buffer,Sum,y*N_Next + x/blockDim.x/2);
            else ScanLoop<_SizeT,Block_N>(s_Buffer,Sum,-1);
            
            if (y == Splict0) Buffer[x] = s_Buffer[threadIdx.x];
            if (y == Splict1) Buffer[x + blockDim.x] = s_Buffer[threadIdx.x + blockDim.x];
        }
    }

    template <
        typename _SizeT,
        //_SizeT   Block_Size,
        int      Block_N>
    __global__ void Step1(
        const _SizeT  N,
        //const _SizeT  N_Next,
              _SizeT* Buffer,
              _SizeT* Sum)
    {
        extern __shared__ _SizeT s_Buffer[];
        _SizeT  y = blockIdx.y * blockDim.y + threadIdx.y;
        _SizeT  x = blockIdx.x * blockDim.x*2 + threadIdx.x;

        if (x >= N) 
             s_Buffer[threadIdx.x] = 0;
        else s_Buffer[threadIdx.x] = Buffer[y*N+x];
        if (x+blockDim.x >= N) 
             s_Buffer[threadIdx.x+blockDim.x] = 0;
        else s_Buffer[threadIdx.x+blockDim.x] = Buffer[y*N+x+blockDim.x];
        __syncthreads();

        ScanLoop<_SizeT,Block_N>(s_Buffer,Sum,y*gridDim.x+blockIdx.x);

        if (x < N) Buffer[y*N+x] = s_Buffer[threadIdx.x];
        if (x+blockDim.x < N) Buffer[y*N+x+blockDim.x] = s_Buffer[threadIdx.x+blockDim.x];
    } // Step1

    template <typename _SizeT>
    __global__ void Step2(
       const _SizeT  N,
       const _SizeT* Sum,
             _SizeT* Buffer)
    {
        _SizeT x = blockIdx.x*blockDim.x+threadIdx.x;
        _SizeT y = blockIdx.y*blockDim.y+threadIdx.y;
        if (x<N) Buffer[y*N+x] += Sum[y*gridDim.x+blockIdx.x];
    } // Step2

    template <
        typename _VertexId,
        typename _SizeT,
        bool EXCLUSIVE>
    __global__ void Step3(
        const _SizeT           N,
        const _SizeT           N_Next,
        const _VertexId* const Select,
        const int*       const Splict,
        const _SizeT*    const Offset,
        const _SizeT*    const Sum,
        const _SizeT*    const Buffer,
              _SizeT*          Result)
    {
        _SizeT x_Next = blockIdx.x + blockIdx.y*gridDim.x;
        _SizeT x = x_Next*blockDim.x + threadIdx.x;

        if (x>=N) return;
        if (Select[x] == 0) {Result[x]=-1; return;}

        _SizeT r=Buffer[x]+Offset[Splict[x]];
        if (x_Next>0) r+=Sum[Splict[x]*N_Next+x_Next];
        if (!EXCLUSIVE) r+=1;
        Result[x]=r;
    } // Step3

    template <
        typename _VertexId,
        typename _SizeT,
        bool EXCLUSIVE>
    __global__ void Step3b(
        const _SizeT           N,
        const _SizeT           N_Next,
        const _SizeT           num_associate,
        const _VertexId*  const Key,
        const int*        const Splict,
        const _VertexId*  const Convertion,
        const _SizeT*     const Offset,
        const _SizeT*     const Sum,
        const _SizeT*     const Buffer,
              _VertexId*        Result,
              _VertexId**       associate_in,
              _VertexId**       associate_out)
    {
        _SizeT x_Next = blockIdx.x + blockIdx.y * gridDim.x;
        _SizeT x = x_Next * blockDim.x + threadIdx.x;

        if (x>=N) return;
        _VertexId key     = Key[x];
        _SizeT    tOffset = Offset[1];
        _SizeT    splict  = Splict[key];
        _SizeT          r = Buffer[x] + Offset[splict];
        if (x_Next>0) r+=Sum[splict*N_Next+x_Next];
        if (!EXCLUSIVE) r+=1;
        Result[r]=Convertion[key];
        
        if (splict>0) 
        for (int i=0;i<num_associate;i++)
        {
            associate_out[i][r-tOffset]=associate_in[i][key];
        }        
    }

    template <
        typename _Type,
        typename _SizeT>
    void Print_Out(_SizeT N,_SizeT M,const _Type* const Array)
    {
        for (_SizeT j=0;j<M;j++)
        {   
            std::cout<<j<<":";
            for (_SizeT i=0;i<N;i++)
            {   
               std::cout<<"\t"<<Array[j*N+i];
            }   
            std::cout<<std::endl;
        }   
    }

    template <
        typename _Type,
        typename _SizeT>
    __host__ void Test_Array(_SizeT N,_SizeT M,_Type* d_Array)
    {
        _Type *h_Array=new _Type[N*M];
        cudaMemcpy(h_Array,d_Array,sizeof(_Type)*N*M,cudaMemcpyDeviceToHost);
        cudaMemcpy(d_Array,h_Array,sizeof(_Type)*N*M,cudaMemcpyHostToDevice);
        Print_Out<_Type,_SizeT>(N,M,h_Array);
        delete[] h_Array;    
    }

template <
    typename VertexId,              // Type of the select array
    typename SizeT,                 // Type of counters
    //SizeT    NUM_ELEMENTS,          // Number of elements to scan
    //SizeT    NUM_ROWS,              // Number of sub-array to splict into
    bool     EXCLUSIVE  = true,     // Whether or not this is an exclusive scan
    SizeT    BLOCK_SIZE = 256,      // Size of element to process by a block
    SizeT    BLOCK_N    = 8>        // log2(BLOCKSIZE)
struct MultiScan
{
    
    __host__ void Scan(
        const SizeT           Num_Elements,
        const SizeT           Num_Rows,
        const VertexId* const d_Select,    // Selection flag, 1 = Selected
        const int*      const d_Splict,    // Spliction mark
        const SizeT*    const d_Offset,    // Offset of each sub-array
              SizeT*          d_Length,    // Length of each sub-array
              SizeT*          d_Result)    // The scan result
    {
        SizeT *History_Size = new SizeT[10];
        SizeT **d_Buffer    = new SizeT*[10];
        SizeT Current_Size  = Num_Elements;
        int   Current_Level = 0;
        dim3  Block_Size,Grid_Size;

        for (int i=0;i<10;i++) d_Buffer[i]=NULL;
        d_Buffer[0]=d_Result;
        History_Size[0] = Current_Size;
        History_Size[1] = Current_Size/BLOCK_SIZE;
        if ((History_Size[0]%BLOCK_SIZE)!=0) History_Size[1]++;
        util::GRError(cudaMalloc(&(d_Buffer[1]), sizeof(SizeT) * History_Size[1] * Num_Rows),
              "cudaMalloc d_Buffer[1] failed", __FILE__, __LINE__);

        //Test_Array<VertexId,SizeT>(Current_Size,SizeT(1),d_Select);
        //Test_Array<int,     SizeT>(Current_Size,SizeT(1),d_Splict);
        while (Current_Size>1)
        {
            //std::cout<<"Current_Level="<<Current_Level<<"\tCurrent_Size="<<Current_Size<<std::endl;
            Block_Size = dim3(BLOCK_SIZE/2, 1, 1);
            if (Current_Level == 0)
            {
                Grid_Size = dim3(History_Size[1]/32, 32, 1);
                if ((History_Size[1]%32) !=0) Grid_Size.x++;
                Step0 <VertexId,SizeT,BLOCK_N> <<<Grid_Size,Block_Size, sizeof(SizeT) * BLOCK_SIZE>>> (
                    Current_Size,
                    Num_Rows,
                    History_Size[1],
                    d_Select,
                    d_Splict,
                    d_Buffer[0],
                    d_Buffer[1]);
                cudaDeviceSynchronize();
                util::GRError("Step0 failed", __FILE__, __LINE__);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level  ],1       ,d_Buffer[Current_Level  ]);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level+1],Num_Rows,d_Buffer[Current_Level+1]);
            } else {
                Grid_Size = dim3(History_Size[Current_Level+1], Num_Rows, 1);
                Step1 <SizeT, BLOCK_N> <<<Grid_Size,Block_Size, sizeof(SizeT) * BLOCK_SIZE>>> (
                    Current_Size,
                    d_Buffer[Current_Level],
                    d_Buffer[Current_Level+1]);
                cudaDeviceSynchronize();
                util::GRError("Step1 failed", __FILE__, __LINE__);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level  ],Num_Rows,d_Buffer[Current_Level  ]);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level+1],Num_Rows,d_Buffer[Current_Level+1]);
            }

            Current_Level++;
            Current_Size = History_Size[Current_Level];
            if (Current_Size > 1)
            {
                History_Size[Current_Level+1] = Current_Size / BLOCK_SIZE;
                if ((Current_Size % BLOCK_SIZE) != 0) History_Size[Current_Level+1]++;
                util::GRError(cudaMalloc(&(d_Buffer[Current_Level+1]), 
                    sizeof(SizeT)*History_Size[Current_Level+1]*Num_Rows),
                    "cudaMalloc d_Buffer failed", __FILE__, __LINE__);
            }
        } // while Current_Size>1
        
        util::GRError(cudaMemcpy(d_Length, d_Buffer[Current_Level], sizeof(SizeT) * Num_Rows, cudaMemcpyDeviceToDevice),
              "cudaMemcpy d_Length failed", __FILE__, __LINE__);
        Current_Level--;
        while (Current_Level>1)
        {
            //std::cout<<"Current_Level="<<Current_Level<<"\tHistory_Size="<<History_Size[Current_Level]<<std::endl;
            Block_Size = dim3(BLOCK_SIZE, 1, 1);
            Grid_Size  = dim3(History_Size[Current_Level], Num_Rows, 1);
            Step2 <SizeT> <<<Grid_Size,Block_Size>>> (
                History_Size[Current_Level-1],
                d_Buffer[Current_Level],
                d_Buffer[Current_Level-1]);
            cudaDeviceSynchronize();
            util::GRError("Step2 failed", __FILE__, __LINE__);
            //Test_Array<SizeT,SizeT>(History_Size[Current_Level  ],Num_Rows,d_Buffer[Current_Level  ]);
            //Test_Array<SizeT,SizeT>(History_Size[Current_Level-1],Num_Rows,d_Buffer[Current_Level-1]);
            Current_Level--;
        } // while Current_Level>1

        Block_Size = dim3(BLOCK_SIZE, 1, 1);
        Grid_Size  = dim3(History_Size[1] /32, 32, 1);
        if ((History_Size[1]%32)!=0) Grid_Size.x++;
        Step3 <VertexId,SizeT,EXCLUSIVE> <<<Grid_Size,Block_Size>>> (
            Num_Elements,
            History_Size[1],
            d_Select,
            d_Splict,
            d_Offset,
            d_Buffer[1],
            d_Buffer[0],
            d_Result);
        cudaDeviceSynchronize();
        util::GRError("Step3 failed", __FILE__, __LINE__);
        //Test_Array<SizeT,SizeT>(History_Size[1],Num_Rows,d_Buffer[1]);
        //Test_Array<SizeT,SizeT>(Num_Elements,1,d_Result);

        for (int i=1;i<10;i++) 
        if (d_Buffer[i]!=NULL) 
        {
            util::GRError(cudaFree(d_Buffer[i]),
                  "cudaFree d_Buffer failed", __FILE__, __LINE__);
            d_Buffer[i]=NULL;
        }
        delete[] d_Buffer;d_Buffer=NULL;
        delete[] History_Size;History_Size=NULL;
    } // Scan

    __host__ void Scan_with_Keys(
        const SizeT            Num_Elements,
        const SizeT            Num_Rows,
        const SizeT            Num_Associate,
        const VertexId*  const d_Keys,
              VertexId*        d_Result,
        const int*       const d_Splict,    // Spliction mark
        const VertexId*  const d_Convertion,
        //const SizeT*     const d_Offset,    // Offset of each sub-array
              SizeT*           d_Length,    // Length of each sub-array
              VertexId**       d_Associate_in,
              VertexId**       d_Associate_out)    // The scan result
    {
        //printf("Scan_width_Keys begin. Num_Elements = %d \n", Num_Elements);fflush(stdout);
        if (Num_Elements <= 0) return;
        SizeT *History_Size = new SizeT[10];
        SizeT **d_Buffer    = new SizeT*[10];
        SizeT Current_Size  = Num_Elements;
        int   Current_Level = 0;
        dim3  Block_Size,Grid_Size;
        SizeT *h_Offset1    = new SizeT[Num_Rows+1];
        SizeT *d_Offset1;
        
        util::GRError(cudaMalloc((void**)&d_Offset1, sizeof(SizeT)*(Num_Rows+1)), "cudaMalloc d_Offset1 failed", __FILE__, __LINE__);

        for (int i=0;i<10;i++) d_Buffer[i]=NULL;
        d_Buffer[0]     = d_Result;
        History_Size[0] = Current_Size;
        History_Size[1] = Current_Size/BLOCK_SIZE;
        if ((History_Size[0]%BLOCK_SIZE)!=0) History_Size[1]++;
        util::GRError(cudaMalloc(&(d_Buffer[1]), sizeof(SizeT) * History_Size[1] * Num_Rows),
              "cudaMalloc d_Buffer[1] failed", __FILE__, __LINE__);
        //printf("Keys: "); Test_Array<SizeT, VertexId> (Num_Elements, 1, d_Keys);
        //printf("Spli: "); Test_Array<SizeT, int     > (7,1,d_Splict);

        while (Current_Size>1 || Current_Level==0)
        {
            Block_Size = dim3(BLOCK_SIZE/2, 1, 1);
            if (Current_Level == 0)
            {
                Grid_Size = dim3(History_Size[1]/32, 32, 1);
                if ((History_Size[1]%32) !=0) Grid_Size.x++;
                Step0b <VertexId,SizeT,BLOCK_N> 
                    <<<Grid_Size,Block_Size, sizeof(SizeT) * BLOCK_SIZE>>> (
                    History_Size[0],
                    Num_Rows,
                    History_Size[1],
                    d_Keys,
                    d_Splict,
                    d_Buffer[0],
                    d_Buffer[1]);
                cudaDeviceSynchronize();
                util::GRError("Step0b failed", __FILE__, __LINE__);
                //printf("Level %d: \n", Current_Level);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level  ],1       ,d_Buffer[Current_Level  ]);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level+1],Num_Rows,d_Buffer[Current_Level+1]);
            } else {
                Grid_Size = dim3(History_Size[Current_Level+1], Num_Rows, 1);
                Step1 <SizeT, BLOCK_N> 
                <<<Grid_Size,Block_Size, sizeof(SizeT) * BLOCK_SIZE>>> (
                    Current_Size,
                    d_Buffer[Current_Level],
                    d_Buffer[Current_Level+1]);
                cudaDeviceSynchronize();
                util::GRError("Step1 failed", __FILE__, __LINE__);
                //printf("Level %d: \n", Current_Level);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level  ],Num_Rows,d_Buffer[Current_Level  ]);
                //Test_Array<SizeT,SizeT>(History_Size[Current_Level+1],Num_Rows,d_Buffer[Current_Level+1]);
            }

            Current_Level++;
            Current_Size = History_Size[Current_Level];
            if (Current_Size > 1)
            {
                History_Size[Current_Level+1] = Current_Size / BLOCK_SIZE;
                if ((Current_Size % BLOCK_SIZE) != 0) History_Size[Current_Level+1]++;
                util::GRError(cudaMalloc(&(d_Buffer[Current_Level+1]), 
                    sizeof(SizeT)*History_Size[Current_Level+1]*Num_Rows),
                    "cudaMalloc d_Buffer failed", __FILE__, __LINE__);
            }
        } // while Current_Size>1
        
        util::GRError(cudaMemcpy(d_Length, d_Buffer[Current_Level], sizeof(SizeT) * Num_Rows, cudaMemcpyDeviceToDevice),
              "cudaMemcpy d_Length failed", __FILE__, __LINE__);
        Current_Level--;
        while (Current_Level>1)
        {
            //std::cout<<"Current_Level="<<Current_Level<<"\tHistory_Size="<<History_Size[Current_Level]<<std::endl;
            Block_Size = dim3(BLOCK_SIZE, 1, 1);
            Grid_Size  = dim3(History_Size[Current_Level], Num_Rows, 1);
            Step2 <SizeT> <<<Grid_Size,Block_Size>>> (
                History_Size[Current_Level-1],
                d_Buffer[Current_Level],
                d_Buffer[Current_Level-1]);
            cudaDeviceSynchronize();
            util::GRError("Step2 failed", __FILE__, __LINE__);
            //printf("Level %d: \n", Current_Level);
            //Test_Array<SizeT,SizeT>(History_Size[Current_Level  ],Num_Rows,d_Buffer[Current_Level  ]);
            //Test_Array<SizeT,SizeT>(History_Size[Current_Level-1],Num_Rows,d_Buffer[Current_Level-1]);
            Current_Level--;
        } // while Current_Level>1

        Block_Size = dim3(BLOCK_SIZE, 1, 1);
        Grid_Size  = dim3(History_Size[1] /32, 32, 1);
        h_Offset1[0]=0;
        util::GRError(cudaMemcpy(&(h_Offset1[1]), d_Length, sizeof(SizeT)*Num_Rows, cudaMemcpyDeviceToHost), 
                     "cudaMemcpy h_Offset1 failed", __FILE__, __LINE__);
        for (int i=0;i<Num_Rows;i++) h_Offset1[i+1]+=h_Offset1[i];
        util::GRError(cudaMemcpy(d_Offset1, h_Offset1, sizeof(SizeT)*(Num_Rows+1), cudaMemcpyHostToDevice),
                     "cudaMemcpy d_Offset1 failed", __FILE__, __LINE__);

        if ((History_Size[1]%32)!=0) Grid_Size.x++;
        //printf("Block_Size = %d,%d,%d Grid_Size = %d,%d,%d\n", Block_Size.x, Block_Size.y, Block_Size.z, Grid_Size.x, Grid_Size.y, Grid_Size.z); fflush(stdout);
        Step3b <VertexId,SizeT,EXCLUSIVE> 
            <<<Grid_Size,Block_Size>>> (
            Num_Elements,
            History_Size[1],
            Num_Associate,
            d_Keys,
            d_Splict,
            d_Convertion,
            d_Offset1,
            d_Buffer[1],
            d_Buffer[0],
            d_Result,
            d_Associate_in,
            d_Associate_out);
        cudaDeviceSynchronize();
        util::GRError("Step3b failed", __FILE__, __LINE__);
        //printf("Level %d: \n", Current_Level);
        //Test_Array<SizeT,SizeT>(History_Size[1],Num_Rows,d_Buffer[1]);
        //Test_Array<SizeT,SizeT>(Num_Elements,1,d_Result);
        //printf("d_Offset: "); Test_Array<SizeT,SizeT>(Num_Rows+1,1,d_Offset);

        for (int i=1;i<10;i++) 
        if (d_Buffer[i]!=NULL) 
        {
            util::GRError(cudaFree(d_Buffer[i]),
                  "cudaFree d_Buffer failed", __FILE__, __LINE__);
            d_Buffer[i]=NULL;
        }
        util::GRError(cudaFree(d_Offset1),"cudaFree d_Offset1 failed", __FILE__, __LINE__); d_Offset1=NULL;
        delete[] h_Offset1;    h_Offset1    = NULL;
        delete[] d_Buffer;     d_Buffer     = NULL;
        delete[] History_Size; History_Size = NULL;
        //printf("Scan_width_keys ended. Num_Elements = %d\n", Num_Elements); fflush(stdout);
    } // Scan_with_Keys

}; // struct MultiScan

} // namespace scan
} // namespace util
} // namespace gunrock
