/* emacs: -*- mode: python-mode; py-indent-offset: 4; indent-tabs-mode: nil -*-
ex: set sts=4 ts=4 sw=4 et:

 *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
 *
 *    SWIG interface to wrap the low-level NIfTI IO libs for Python
 *
 *   See COPYING file distributed along with the PyNIfTI package for the
 *   copyright and license terms.
 *
 *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
*/

%define DOCSTRING
"
This module provide the all functions and datatypes implemented
in the low-level C library libniftiio and the NIfTI-1 header.

At the moment no additional documentation is provided here. Please see the
intensively documented source code of the nifti C libs to learn about the
capabilities of the library.
"
%enddef

%module (package="cnifti", docstring=DOCSTRING) clib
%{
#include <nifti1_io.h>
#include <znzlib.h>

#include <Python.h>
#include <numpy/arrayobject.h>

/* low tech wrapper function to set values of a mat44 struct */
static void set_mat44(mat44* m,
                      float a1, float a2, float a3, float a4,
                      float b1, float b2, float b3, float b4,
                      float c1, float c2, float c3, float c4,
                      float d1, float d2, float d3, float d4 )
{
    m->m[0][0] = a1; m->m[0][1] = a2; m->m[0][2] = a3; m->m[0][3] = a4;
    m->m[1][0] = b1; m->m[1][1] = b2; m->m[1][2] = b3; m->m[1][3] = b4;
    m->m[2][0] = c1; m->m[2][1] = c2; m->m[2][2] = c3; m->m[2][3] = c4;
    m->m[3][0] = d1; m->m[3][1] = d2; m->m[3][2] = d3; m->m[3][3] = d4;
}

/* convert mat44 struct into a numpy float array */
static PyObject* mat442array(mat44 _mat)
{
    npy_intp dims[2] = {4,4};

    PyObject* array = 0;
    array = PyArray_SimpleNew ( 2, dims, NPY_FLOAT );

    /* mat44 subscription is [row][column] */
    PyArrayObject* a = (PyArrayObject*) array;

    float* data = (float *)a->data;

    int i,j;

    for (i = 0; i<4; i+=1)
    {
        for (j = 0; j<4; j+=1)
        {
            data[4*i+j] = _mat.m[i][j];
        }
    }

    return PyArray_Return ( (PyArrayObject*) array  );
}

/********************************************************
 *
 * Wrapping the image array with a NumPy array.
 *
 * This is a revised version following the solution
 * outlined here: http://blog.enthought.com/?p=62
 * 
 *******************************************************/

/* define a new python object type that performs the array
   data de-allocation when the ref count goes to zero */
typedef struct
{
    PyObject_HEAD
    void *memory;
} _MyDeallocObject;

static void _mydealloc_dealloc(_MyDeallocObject *self)
{
    free(self->memory);
    self->ob_type->tp_free((PyObject *)self);
}

static PyTypeObject _MyDeallocType = {
    PyObject_HEAD_INIT(NULL)
    0, "mydeallocator", sizeof(_MyDeallocObject), 0, _mydealloc_dealloc,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Py_TPFLAGS_DEFAULT,
    "Internal deallocator object",
};

static PyObject* wrapImageDataWithArray(nifti_image* _img)
{
    if (!_img)
    {
        PyErr_SetString(
            PyExc_RuntimeError,
            "Zero pointer passed instead of valid nifti_image struct.");
        return(NULL);
    }

    int array_type=0;

    /* translate nifti datatypes to numpy datatypes */
    switch(_img->datatype)
    {
      case NIFTI_TYPE_UINT8:
          array_type = NPY_UINT8;
          break;
      case NIFTI_TYPE_INT8:
          array_type = NPY_INT8;
          break;
      case NIFTI_TYPE_UINT16:
          array_type = NPY_UINT16;
          break;
      case NIFTI_TYPE_INT16:
          array_type = NPY_INT16;
          break;
      case NIFTI_TYPE_UINT32:
          array_type = NPY_UINT32;
          break;
      case NIFTI_TYPE_INT32:
          array_type = NPY_INT32;
          break;
      case NIFTI_TYPE_UINT64:
          array_type = NPY_UINT64;
          break;
      case NIFTI_TYPE_INT64:
          array_type = NPY_INT64;
          break;
      case NIFTI_TYPE_FLOAT32:
          array_type = NPY_FLOAT32;
          break;
      case NIFTI_TYPE_FLOAT64:
          array_type = NPY_FLOAT64;
          break;
      case NIFTI_TYPE_COMPLEX64:
          array_type = NPY_COMPLEX64;
          break;
      case NIFTI_TYPE_COMPLEX128:
          array_type = NPY_COMPLEX128;
          break;
      default:
          PyErr_SetString(PyExc_RuntimeError, "Unsupported datatype");
          return(NULL);
    }

    /* array object */
    PyObject* volarray = 0;

    /* Get the number of dimensions from the niftifile and
     * reverse the order for the conversion to a numpy array.
     * Doing so will make users access to the data more convenient:
     * a 3d volume from a 4d file can be index by a single number.
     */
    int ndims, k;
    /* Array dimensions need to be an integer type whose byte size matches
     * the pointer size on the compiled platform.  This way the dimension
     * along that array axis is only limited by the available memory.
     * The Numpy C-API provides a type npy_intp for this purpose.
     * This is required by all PyArray_New* functions.
     */
    npy_intp ar_dim[7];

    /* first item in dim array stores the number of dims */
    ndims = (int) _img->dim[0];
    /* reverse the order */
    for (k=0; k<ndims; k++)
    {
        ar_dim[k] = (int) _img->dim[ndims-k];
    }

    /* create numpy array */
    volarray = PyArray_SimpleNewFromData(ndims, ar_dim, array_type, _img->data);

    /* create deallocator */
    PyObject* newobj=NULL;
    newobj = PyObject_New(_MyDeallocObject, &_MyDeallocType);
    /* assign the image data pointer */
    ((_MyDeallocObject *)newobj)->memory = _img->data;
    /* let the deallocator manage the array memory management */
    PyArray_BASE(volarray) = newobj;

    return PyArray_Return ( (PyArrayObject*) volarray  );
}

static void detachDataFromImage(nifti_image* _nim)
{
    _nim->data = NULL;
}


int allocateImageMemory(nifti_image* _nim)
{
  if (_nim == NULL)
  {
    fprintf(stderr, "NULL pointer passed to allocateImageMemory()");
    return(0);
  }

  if (_nim->data != NULL)
  {
    fprintf(
        stderr,
        "There seems to be allocated memory already (valid nim->data pointer found).");
    return(0);
  }

  /* allocate memory */
  _nim->data = (void*) calloc(1,nifti_get_volsize(_nim));

  if (_nim->data == NULL)
  {
    fprintf(stderr,
            "Failed to allocate %d bytes for image data\n",
            (int)nifti_get_volsize(_nim));
    return(0);
  }

  return(1);
}

int xyzt2space(char val)
{
  return XYZT_TO_SPACE(val);
}

int xyzt2time(char val)
{
  return XYZT_TO_TIME(val);
}

char spacetime2xyzt(int sp, int t)
{
  return SPACE_TIME_TO_XYZT(sp, t);
}

%}


%init
%{
    import_array();

    /* initialize the new Python type for memory deallocation */
    _MyDeallocType.tp_new = PyType_GenericNew;
    if (PyType_Ready(&_MyDeallocType) < 0)
        return;
%}

%include "typemaps.i"
/* Need to put before nifti1_io.h to overwrite function prototype with this
 * typemap. */
void nifti_mat44_to_quatern( mat44 R ,
                             float *OUTPUT, float *OUTPUT, float *OUTPUT,
                             float *OUTPUT, float *OUTPUT, float *OUTPUT,
                             float *OUTPUT, float *OUTPUT, float *OUTPUT,
                             float *OUTPUT );

void nifti_mat44_to_orientation( mat44 R , int *OUTPUT, int *OUTPUT,
                                 int *OUTPUT );


%include znzlib.h
%include nifti1.h
%include nifti1_io.h

static PyObject * wrapImageDataWithArray(nifti_image* _img);
static void detachDataFromImage(nifti_image* _nim);
int allocateImageMemory(nifti_image* _nim);

static PyObject* mat442array(mat44 _mat);
static void set_mat44(mat44* m,
                      float a1, float a2, float a3, float a4,
                      float b1, float b2, float b3, float b4,
                      float c1, float c2, float c3, float c4,
                      float d1, float d2, float d3, float d4 );

int xyzt2space(char val);
int xyzt2time(char val);
char spacetime2xyzt(int sp, int t);

%include "cpointer.i"
%pointer_functions(short, shortp);
%pointer_functions(int, intp);
%pointer_functions(unsigned int, uintp);
%pointer_functions(float, floatp);
%pointer_functions(double, doublep);
%pointer_functions(char, charp);

%include "carrays.i"
%array_class(short, shortArray);
%array_class(int, intArray);
%array_class(unsigned int, uintArray);
%array_class(float, floatArray);
%array_class(double, doubleArray);
%array_class(nifti1_extension, extensionArray);


